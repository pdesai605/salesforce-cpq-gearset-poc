/**
 * Deal Desk governance rules for Salesforce CPQ quotes.
 *
 * Every quote is scored on save:
 *   - Overall discount off list (Net Amount vs List Amount)
 *   - Number of lines priced below the product floor price
 *   - Deal size
 *
 * Discount tiers come from Discount_Threshold__mdt, so the business can change
 * thresholds as configuration and promote them through the release pipeline
 * without touching code.
 */
public with sharing class DealDeskService {
    public static final String STATUS_NOT_REQUIRED = 'Not Required';
    public static final String STATUS_PENDING = 'Pending';
    public static final String STATUS_APPROVED = 'Approved';
    public static final String STATUS_REJECTED = 'Rejected';

    public static final Decimal LARGE_DEAL_THRESHOLD = 100000;
    private static final Integer POINTS_PER_DISCOUNT_PERCENT = 2;
    private static final Integer POINTS_PER_BELOW_FLOOR_LINE = 15;
    private static final Integer POINTS_FOR_LARGE_DEAL = 10;
    private static final Integer MAX_SCORE = 100;

    @TestVisible
    private static List<Discount_Threshold__mdt> thresholdOverride;

    /**
     * Evaluates quotes in a before-insert / before-update context.
     * Field values are set in memory; no DML is performed.
     */
    public static void evaluateQuotes(List<SBQQ__Quote__c> quotes, Map<Id, SBQQ__Quote__c> oldMap) {
        List<Discount_Threshold__mdt> thresholds = getThresholds();

        for (SBQQ__Quote__c quote : quotes) {
            SBQQ__Quote__c oldQuote = (oldMap == null || quote.Id == null) ? null : oldMap.get(quote.Id);

            Decimal discount = calculateDiscountPercent(quote.SBQQ__ListAmount__c, quote.SBQQ__NetAmount__c);
            Integer belowFloorLines = quote.Below_Floor_Line_Count__c == null
                ? 0
                : quote.Below_Floor_Line_Count__c.intValue();
            Discount_Threshold__mdt tier = resolveTier(discount, thresholds);
            Boolean needsApproval = (tier != null && tier.Requires_Approval__c) || belowFloorLines > 0;
            Decimal previousDiscount = oldQuote == null ? null : oldQuote.Quote_Discount_Percent__c;

            quote.Quote_Discount_Percent__c = discount;
            quote.Discount_Tier__c = tier == null ? null : tier.Tier__c;
            quote.Deal_Risk_Score__c = calculateRiskScore(discount, belowFloorLines, quote.SBQQ__NetAmount__c);
            quote.Requires_Deal_Desk_Approval__c = needsApproval;
            quote.Approval_Status__c = nextApprovalStatus(
                needsApproval,
                quote.Approval_Status__c,
                previousDiscount,
                discount
            );
        }
    }

    /** Overall discount in percent (0-100). Returns 0 when there is no list amount yet. */
    public static Decimal calculateDiscountPercent(Decimal listAmount, Decimal netAmount) {
        if (listAmount == null || listAmount <= 0 || netAmount == null) {
            return 0;
        }
        Decimal percent = (1 - (netAmount / listAmount)) * 100;
        return percent < 0 ? 0 : percent.setScale(2, System.RoundingMode.HALF_UP);
    }

    /** Picks the lowest tier whose Max Discount % covers the discount. */
    public static Discount_Threshold__mdt resolveTier(
        Decimal discountPercent,
        List<Discount_Threshold__mdt> thresholds
    ) {
        List<Discount_Threshold__mdt> sorted = sortByMaxDiscount(thresholds);
        if (sorted.isEmpty()) {
            return null;
        }
        Decimal discount = discountPercent == null ? 0 : discountPercent;
        for (Discount_Threshold__mdt threshold : sorted) {
            if (discount <= threshold.Max_Discount_Percent__c) {
                return threshold;
            }
        }
        return sorted[sorted.size() - 1];
    }

    /** 0-100 risk score: discount depth, below-floor lines and deal size. */
    public static Integer calculateRiskScore(Decimal discountPercent, Integer belowFloorLines, Decimal netAmount) {
        Decimal score = (discountPercent == null ? 0 : discountPercent) * POINTS_PER_DISCOUNT_PERCENT;
        score += (belowFloorLines == null ? 0 : belowFloorLines) * POINTS_PER_BELOW_FLOOR_LINE;
        if (netAmount != null && netAmount >= LARGE_DEAL_THRESHOLD) {
            score += POINTS_FOR_LARGE_DEAL;
        }
        Long rounded = score.round(System.RoundingMode.HALF_UP);
        return Math.min(MAX_SCORE, rounded.intValue());
    }

    /**
     * Approval lifecycle:
     *  - No approval needed            -> Not Required
     *  - Needs approval, not requested -> Pending
     *  - Approved, then discount grows -> back to Pending (approval no longer covers the deal)
     *  - Otherwise keep current status (Pending / Approved / Rejected)
     */
    public static String nextApprovalStatus(
        Boolean needsApproval,
        String currentStatus,
        Decimal previousDiscount,
        Decimal newDiscount
    ) {
        if (needsApproval != true) {
            return STATUS_NOT_REQUIRED;
        }
        if (String.isBlank(currentStatus) || currentStatus == STATUS_NOT_REQUIRED) {
            return STATUS_PENDING;
        }
        if (
            currentStatus == STATUS_APPROVED &&
            previousDiscount != null &&
            newDiscount != null &&
            newDiscount > previousDiscount
        ) {
            return STATUS_PENDING;
        }
        return currentStatus;
    }

    public static List<Discount_Threshold__mdt> getThresholds() {
        if (thresholdOverride != null) {
            return thresholdOverride;
        }
        return Discount_Threshold__mdt.getAll().values();
    }

    private static List<Discount_Threshold__mdt> sortByMaxDiscount(List<Discount_Threshold__mdt> thresholds) {
        List<Discount_Threshold__mdt> sorted = new List<Discount_Threshold__mdt>();
        if (thresholds == null) {
            return sorted;
        }
        for (Discount_Threshold__mdt candidate : thresholds) {
            if (candidate.Max_Discount_Percent__c == null) {
                continue;
            }
            Integer position = 0;
            while (
                position < sorted.size() &&
                sorted[position].Max_Discount_Percent__c <= candidate.Max_Discount_Percent__c
            ) {
                position++;
            }
            if (position == sorted.size()) {
                sorted.add(candidate);
            } else {
                sorted.add(position, candidate);
            }
        }
        return sorted;
    }
}
