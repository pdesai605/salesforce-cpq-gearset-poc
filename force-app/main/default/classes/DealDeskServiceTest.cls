/**
 * Unit tests for the Deal Desk rules. No DML: these run in milliseconds and
 * act as the fast quality gate on every pull request.
 */
@IsTest
private class DealDeskServiceTest {
    private static List<Discount_Threshold__mdt> thresholds() {
        // Deliberately unsorted to prove the service sorts tiers itself
        return new List<Discount_Threshold__mdt>{
            new Discount_Threshold__mdt(
                Tier__c = 'Executive',
                Max_Discount_Percent__c = 100,
                Requires_Approval__c = true
            ),
            new Discount_Threshold__mdt(
                Tier__c = 'Standard',
                Max_Discount_Percent__c = 10,
                Requires_Approval__c = false
            ),
            new Discount_Threshold__mdt(Tier__c = 'Elevated', Max_Discount_Percent__c = 25, Requires_Approval__c = true)
        };
    }

    private static Id fakeQuoteId(Integer n) {
        String prefix = SBQQ__Quote__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix();
        return Id.valueOf(prefix + String.valueOf(n).leftPad(12, '0'));
    }

    /** Builds a quote with values in CPQ roll-up fields, which cannot be set directly in Apex. */
    private static SBQQ__Quote__c quote(
        Id quoteId,
        Decimal listAmount,
        Decimal netAmount,
        Integer belowFloor,
        String status,
        Decimal discount
    ) {
        Map<String, Object> values = new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'SBQQ__Quote__c' },
            'SBQQ__ListAmount__c' => listAmount,
            'SBQQ__NetAmount__c' => netAmount,
            'Below_Floor_Line_Count__c' => belowFloor,
            'Approval_Status__c' => status,
            'Quote_Discount_Percent__c' => discount
        };
        if (quoteId != null) {
            values.put('Id', quoteId);
        }
        return (SBQQ__Quote__c) JSON.deserialize(JSON.serialize(values), SBQQ__Quote__c.class);
    }

    @IsTest
    static void calculatesDiscountPercent() {
        Assert.areEqual(20.00, DealDeskService.calculateDiscountPercent(1000, 800), 'Net 800 on list 1000 is 20% off');
        Assert.areEqual(
            0.00,
            DealDeskService.calculateDiscountPercent(null, 800),
            'No list amount means no discount yet'
        );
        Assert.areEqual(
            0.00,
            DealDeskService.calculateDiscountPercent(0, 800),
            'Zero list amount is treated as no discount'
        );
        Assert.areEqual(
            0.00,
            DealDeskService.calculateDiscountPercent(1000, 1200),
            'Mark-ups never produce a negative discount'
        );
    }

    @IsTest
    static void resolvesTierFromConfiguration() {
        List<Discount_Threshold__mdt> config = thresholds();
        Assert.areEqual('Standard', DealDeskService.resolveTier(5, config).Tier__c, '5% is Standard');
        Assert.areEqual('Standard', DealDeskService.resolveTier(10, config).Tier__c, 'Boundary is inclusive');
        Assert.areEqual('Elevated', DealDeskService.resolveTier(18, config).Tier__c, '18% is Elevated');
        Assert.areEqual('Executive', DealDeskService.resolveTier(40, config).Tier__c, '40% is Executive');
        Assert.areEqual(
            'Executive',
            DealDeskService.resolveTier(150, config).Tier__c,
            'Above every tier falls back to the highest'
        );
        Assert.isNull(
            DealDeskService.resolveTier(15, new List<Discount_Threshold__mdt>()),
            'No configuration returns no tier'
        );
    }

    @IsTest
    static void scoresRisk() {
        Assert.areEqual(40, DealDeskService.calculateRiskScore(20, 0, 50000), '20% discount only');
        Assert.areEqual(
            65,
            DealDeskService.calculateRiskScore(20, 1, 150000),
            'Discount + one below-floor line + large deal'
        );
        Assert.areEqual(100, DealDeskService.calculateRiskScore(60, 2, 200000), 'Score is capped at 100');
        Assert.areEqual(0, DealDeskService.calculateRiskScore(null, null, null), 'Missing values score zero');
    }

    @IsTest
    static void movesThroughApprovalLifecycle() {
        Assert.areEqual(
            'Not Required',
            DealDeskService.nextApprovalStatus(false, 'Pending', 5, 5),
            'No approval needed'
        );
        Assert.areEqual('Pending', DealDeskService.nextApprovalStatus(true, null, null, 20), 'New approval request');
        Assert.areEqual(
            'Pending',
            DealDeskService.nextApprovalStatus(true, 'Not Required', 5, 20),
            'Deal became risky'
        );
        Assert.areEqual(
            'Pending',
            DealDeskService.nextApprovalStatus(true, 'Approved', 20, 30),
            'Discount grew after approval'
        );
        Assert.areEqual(
            'Approved',
            DealDeskService.nextApprovalStatus(true, 'Approved', 20, 20),
            'Approval still covers the deal'
        );
        Assert.areEqual(
            'Approved',
            DealDeskService.nextApprovalStatus(true, 'Approved', 20, 15),
            'Lower discount keeps approval'
        );
        Assert.areEqual('Rejected', DealDeskService.nextApprovalStatus(true, 'Rejected', 20, 20), 'Rejection is kept');
    }

    @IsTest
    static void calculatesFloorAndMargin() {
        Assert.isTrue(FloorPricingService.isBelowFloor(80, 90), '80 is below a 90 floor');
        Assert.isFalse(FloorPricingService.isBelowFloor(90, 90), 'Equal to floor is allowed');
        Assert.isFalse(FloorPricingService.isBelowFloor(80, null), 'No floor configured');
        Assert.areEqual(37.50, FloorPricingService.calculateMarginPercent(80, 50), '(80 - 50) / 80');
        Assert.isNull(FloorPricingService.calculateMarginPercent(0, 50), 'No margin on a zero price');
        Assert.isNull(FloorPricingService.calculateMarginPercent(80, null), 'No margin without cost');
    }

    @IsTest
    static void evaluatesQuotesInMemory() {
        DealDeskService.thresholdOverride = thresholds();

        SBQQ__Quote__c deepDiscount = quote(null, 10000, 7000, 0, null, null);
        SBQQ__Quote__c belowFloor = quote(null, 10000, 9500, 2, null, null);
        SBQQ__Quote__c clean = quote(null, 10000, 9500, 0, null, null);

        Test.startTest();
        DealDeskService.evaluateQuotes(new List<SBQQ__Quote__c>{ deepDiscount, belowFloor, clean }, null);
        Test.stopTest();

        Assert.areEqual(30.00, deepDiscount.Quote_Discount_Percent__c, '30% off list');
        Assert.areEqual('Executive', deepDiscount.Discount_Tier__c, '30% is Executive');
        Assert.areEqual(60, deepDiscount.Deal_Risk_Score__c.intValue(), '30 x 2 points');
        Assert.isTrue(deepDiscount.Requires_Deal_Desk_Approval__c, 'Executive tier needs approval');
        Assert.areEqual('Pending', deepDiscount.Approval_Status__c, 'Approval requested automatically');

        Assert.areEqual('Standard', belowFloor.Discount_Tier__c, '5% is Standard');
        Assert.isTrue(belowFloor.Requires_Deal_Desk_Approval__c, 'Below-floor lines always need approval');
        Assert.areEqual(40, belowFloor.Deal_Risk_Score__c.intValue(), '5% x 2 + 2 lines x 15');

        Assert.isFalse(clean.Requires_Deal_Desk_Approval__c, 'Clean deal flows straight through');
        Assert.areEqual('Not Required', clean.Approval_Status__c, 'No approval needed');
    }

    @IsTest
    static void reopensApprovalWhenDiscountIncreases() {
        DealDeskService.thresholdOverride = thresholds();
        Id quoteId = fakeQuoteId(1);
        SBQQ__Quote__c oldQuote = quote(quoteId, 10000, 8000, 0, 'Approved', 20.00);
        SBQQ__Quote__c newQuote = quote(quoteId, 10000, 7000, 0, 'Approved', 20.00);

        DealDeskService.evaluateQuotes(
            new List<SBQQ__Quote__c>{ newQuote },
            new Map<Id, SBQQ__Quote__c>{ quoteId => oldQuote }
        );

        Assert.areEqual('Pending', newQuote.Approval_Status__c, 'A bigger discount needs a fresh approval');
    }

    @IsTest
    static void handlersRespectBypassSwitch() {
        SBQQ__Quote__c untouched = quote(null, 10000, 5000, 0, null, null);

        QuoteTriggerHandler.bypass = true;
        QuoteTriggerHandler.handle(System.TriggerOperation.BEFORE_INSERT, new List<SBQQ__Quote__c>{ untouched }, null);
        QuoteTriggerHandler.bypass = false;
        QuoteTriggerHandler.handle(System.TriggerOperation.AFTER_INSERT, new List<SBQQ__Quote__c>{ untouched }, null);

        QuoteLineTriggerHandler.bypass = true;
        QuoteLineTriggerHandler.handle(System.TriggerOperation.BEFORE_INSERT, new List<SBQQ__QuoteLine__c>());
        QuoteLineTriggerHandler.bypass = false;
        QuoteLineTriggerHandler.handle(System.TriggerOperation.AFTER_INSERT, new List<SBQQ__QuoteLine__c>());

        Assert.isNull(untouched.Deal_Risk_Score__c, 'Bypassed and after-save calls do not evaluate the quote');
    }
}
