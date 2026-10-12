/**
 * End-to-end tests: real quote and quote line records, triggers, the roll-up
 * summary, the record-triggered flow and the LWC controller working together.
 *
 * CPQ package triggers are disabled while test data is created, so these tests
 * check our automation only and do not depend on the CPQ pricing engine.
 */
@IsTest
private class DealDeskIntegrationTest {
    private static final Decimal FLOOR_PRICE = 90;
    private static final Decimal UNIT_COST = 50;

    @TestSetup
    static void setup() {
        User admin = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        System.runAs(admin) {
            List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
            for (PermissionSet ps : [
                SELECT Id
                FROM PermissionSet
                WHERE Name IN ('Deal_Desk_User', 'Deal_Desk_Approver')
            ]) {
                assignments.add(new PermissionSetAssignment(AssigneeId = admin.Id, PermissionSetId = ps.Id));
            }
            insert assignments;
        }

        SBQQ.TriggerControl.disable();
        try {
            Product2 product = new Product2(
                Name = 'Nimbus Core Licence (Test)',
                ProductCode = 'NIMBUS-CORE-TEST',
                IsActive = true,
                Floor_Price__c = FLOOR_PRICE,
                Unit_Cost__c = UNIT_COST
            );
            insert product;

            Account account = new Account(Name = 'Deal Desk Test Account');
            insert account;

            SBQQ__Quote__c quote = new SBQQ__Quote__c(SBQQ__Account__c = account.Id);
            insert quote;

            insert new SBQQ__QuoteLine__c(
                SBQQ__Quote__c = quote.Id,
                SBQQ__Product__c = product.Id,
                SBQQ__Quantity__c = 1,
                SBQQ__ListPrice__c = 100,
                SBQQ__NetPrice__c = 80
            );
        } finally {
            SBQQ.TriggerControl.enable();
        }
    }

    private static SBQQ__Quote__c getQuote() {
        return [
            SELECT
                Id,
                Below_Floor_Line_Count__c,
                Requires_Deal_Desk_Approval__c,
                Approval_Status__c,
                Deal_Risk_Score__c,
                Discount_Tier__c
            FROM SBQQ__Quote__c
            LIMIT 1
        ];
    }

    private static SBQQ__QuoteLine__c getLine() {
        return [
            SELECT Id, Floor_Price__c, Below_Floor__c, Line_Margin_Percent__c, SBQQ__NetPrice__c
            FROM SBQQ__QuoteLine__c
            LIMIT 1
        ];
    }

    @IsTest
    static void stampsFloorPricingOnQuoteLines() {
        SBQQ__QuoteLine__c line = getLine();
        Assert.areEqual(FLOOR_PRICE, line.Floor_Price__c, 'Floor price copied from the product');
        Assert.isTrue(line.Below_Floor__c, 'Net 80 is below the 90 floor');
        Assert.areEqual(37.50, line.Line_Margin_Percent__c, '(80 - 50) / 80');
    }

    @IsTest
    static void belowFloorLineTriggersDealDeskApproval() {
        SBQQ__Quote__c quote = getQuote();
        Assert.areEqual(1, quote.Below_Floor_Line_Count__c.intValue(), 'Roll-up counts the below-floor line');
        Assert.isTrue(quote.Requires_Deal_Desk_Approval__c, 'Below-floor pricing needs approval');
        Assert.areEqual('Pending', quote.Approval_Status__c, 'Approval requested automatically');
        Assert.isTrue(quote.Deal_Risk_Score__c >= 15, 'Below-floor line adds risk');
    }

    @IsTest
    static void raisingPriceAboveFloorClearsTheFlag() {
        SBQQ__QuoteLine__c line = getLine();
        line.SBQQ__NetPrice__c = 95;

        Test.startTest();
        SBQQ.TriggerControl.disable();
        update line;
        SBQQ.TriggerControl.enable();
        Test.stopTest();

        SBQQ__QuoteLine__c updatedLine = getLine();
        SBQQ__Quote__c quote = getQuote();
        Assert.isFalse(updatedLine.Below_Floor__c, '95 is above the floor');
        Assert.areEqual(0, quote.Below_Floor_Line_Count__c.intValue(), 'Roll-up recalculated');
        Assert.areEqual(
            quote.Discount_Tier__c != 'Standard',
            quote.Requires_Deal_Desk_Approval__c,
            'Only the discount tier decides approval once pricing is above floor'
        );
    }

    @IsTest
    static void controllerReturnsSummaryAndApproves() {
        SBQQ__Quote__c quote = getQuote();

        Test.startTest();
        DealDeskController.DealDeskSummary summary = DealDeskController.getSummary(quote.Id);
        DealDeskController.updateApprovalStatus(quote.Id, 'Approved', 'Approved for strategic logo.');
        Test.stopTest();

        Assert.areEqual(1, summary.lines.size(), 'One line returned');
        Assert.isTrue(summary.lines[0].belowFloor, 'Line flagged in the panel');
        Assert.isTrue(summary.canApprove, 'Test user holds the approver permission');
        Assert.areEqual('Approved', getQuote().Approval_Status__c, 'Approval saved');
    }

    @IsTest
    static void rejectsInvalidStatus() {
        SBQQ__Quote__c quote = getQuote();
        Boolean failed = false;
        try {
            DealDeskController.updateApprovalStatus(quote.Id, 'Maybe', null);
        } catch (AuraHandledException e) {
            failed = true;
        }
        Assert.isTrue(failed, 'Only Approved or Rejected are accepted');
    }

    @IsTest
    static void blocksUsersWithoutApproverPermission() {
        SBQQ__Quote__c quote = getQuote();
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String unique = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        User rep = new User(
            Alias = 'ddrep',
            Email = 'ddrep' + unique + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Rep',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            Username = 'ddrep' + unique + '@example.com.dealdesk'
        );

        Boolean failed = false;
        System.runAs(rep) {
            try {
                DealDeskController.updateApprovalStatus(quote.Id, 'Approved', null);
            } catch (AuraHandledException e) {
                failed = true;
            }
        }
        Assert.isTrue(failed, 'Sales reps cannot approve their own deals');
    }

    @IsTest
    static void createsDealDeskTaskWhenApprovalIsRequested() {
        Integer tasks = [SELECT COUNT() FROM Task WHERE Subject LIKE 'Deal Desk review required%'];
        Assert.isTrue(tasks >= 1, 'Flow creates a review task when the quote goes to Pending');
    }
}
