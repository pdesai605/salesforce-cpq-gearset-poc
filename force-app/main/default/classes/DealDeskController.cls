/**
 * Apex controller for the dealDeskPanel LWC on the CPQ Quote record page.
 * Runs all queries and DML in user mode, so field-level security and sharing are enforced.
 */
public with sharing class DealDeskController {
    public static final String APPROVER_PERMISSION = 'Deal_Desk_Approver';
    private static final Set<String> ALLOWED_DECISIONS = new Set<String>{
        DealDeskService.STATUS_APPROVED,
        DealDeskService.STATUS_REJECTED
    };

    @AuraEnabled(cacheable=true)
    public static DealDeskSummary getSummary(Id quoteId) {
        if (quoteId == null) {
            throw new AuraHandledException('Quote Id is required.');
        }

        List<SBQQ__Quote__c> quotes = [
            SELECT
                Id,
                Name,
                SBQQ__NetAmount__c,
                SBQQ__ListAmount__c,
                Quote_Discount_Percent__c,
                Deal_Risk_Score__c,
                Discount_Tier__c,
                Requires_Deal_Desk_Approval__c,
                Approval_Status__c,
                Below_Floor_Line_Count__c,
                Deal_Desk_Notes__c
            FROM SBQQ__Quote__c
            WHERE Id = :quoteId
            WITH USER_MODE
            LIMIT 1
        ];
        if (quotes.isEmpty()) {
            throw new AuraHandledException('Quote not found or you do not have access to it.');
        }
        SBQQ__Quote__c quote = quotes[0];

        DealDeskSummary summary = new DealDeskSummary();
        summary.quoteId = quote.Id;
        summary.quoteName = quote.Name;
        summary.netAmount = quote.SBQQ__NetAmount__c;
        summary.listAmount = quote.SBQQ__ListAmount__c;
        summary.discountPercent = quote.Quote_Discount_Percent__c;
        summary.riskScore = quote.Deal_Risk_Score__c == null ? 0 : quote.Deal_Risk_Score__c.intValue();
        summary.tier = quote.Discount_Tier__c;
        summary.requiresApproval = quote.Requires_Deal_Desk_Approval__c;
        summary.approvalStatus = quote.Approval_Status__c;
        summary.belowFloorLines = quote.Below_Floor_Line_Count__c == null
            ? 0
            : quote.Below_Floor_Line_Count__c.intValue();
        summary.notes = quote.Deal_Desk_Notes__c;
        summary.canApprove = FeatureManagement.checkPermission(APPROVER_PERMISSION);
        summary.lines = new List<LineSummary>();

        for (SBQQ__QuoteLine__c line : [
            SELECT
                Id,
                SBQQ__ProductName__c,
                SBQQ__Quantity__c,
                SBQQ__NetPrice__c,
                Floor_Price__c,
                Below_Floor__c,
                Line_Margin_Percent__c
            FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Quote__c = :quoteId
            WITH USER_MODE
            ORDER BY SBQQ__Number__c
            LIMIT 200
        ]) {
            LineSummary row = new LineSummary();
            row.id = line.Id;
            row.productName = line.SBQQ__ProductName__c;
            row.quantity = line.SBQQ__Quantity__c;
            row.netPrice = line.SBQQ__NetPrice__c;
            row.floorPrice = line.Floor_Price__c;
            row.belowFloor = line.Below_Floor__c;
            row.marginPercent = line.Line_Margin_Percent__c;
            summary.lines.add(row);
        }
        return summary;
    }

    /** Approve or reject a quote. Requires the Deal_Desk_Approver custom permission. */
    @AuraEnabled
    public static void updateApprovalStatus(Id quoteId, String status, String notes) {
        validateDecision(quoteId, status);

        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            Id = quoteId,
            Approval_Status__c = status,
            Deal_Desk_Notes__c = notes
        );
        try {
            Database.update(quote, AccessLevel.USER_MODE);
        } catch (Exception e) {
            AuraHandledException wrapped = new AuraHandledException(e.getMessage());
            wrapped.setMessage(e.getMessage());
            throw wrapped;
        }
    }

    private static void validateDecision(Id quoteId, String status) {
        if (!FeatureManagement.checkPermission(APPROVER_PERMISSION)) {
            throw new AuraHandledException('Only Deal Desk approvers can approve or reject quotes.');
        }
        if (!ALLOWED_DECISIONS.contains(status)) {
            throw new AuraHandledException('Status must be Approved or Rejected.');
        }
        if (quoteId == null) {
            throw new AuraHandledException('Quote Id is required.');
        }
    }

    public class DealDeskSummary {
        @AuraEnabled
        public Id quoteId;
        @AuraEnabled
        public String quoteName;
        @AuraEnabled
        public Decimal netAmount;
        @AuraEnabled
        public Decimal listAmount;
        @AuraEnabled
        public Decimal discountPercent;
        @AuraEnabled
        public Integer riskScore;
        @AuraEnabled
        public String tier;
        @AuraEnabled
        public Boolean requiresApproval;
        @AuraEnabled
        public String approvalStatus;
        @AuraEnabled
        public Integer belowFloorLines;
        @AuraEnabled
        public String notes;
        @AuraEnabled
        public Boolean canApprove;
        @AuraEnabled
        public List<LineSummary> lines;
    }

    public class LineSummary {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String productName;
        @AuraEnabled
        public Decimal quantity;
        @AuraEnabled
        public Decimal netPrice;
        @AuraEnabled
        public Decimal floorPrice;
        @AuraEnabled
        public Boolean belowFloor;
        @AuraEnabled
        public Decimal marginPercent;
    }
}
