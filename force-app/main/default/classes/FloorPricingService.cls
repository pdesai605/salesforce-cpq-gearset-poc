/**
 * Floor price and margin rules for individual CPQ quote lines.
 */
public with sharing class FloorPricingService {
    /** True when the net unit price is below the configured floor. */
    public static Boolean isBelowFloor(Decimal netPrice, Decimal floorPrice) {
        return floorPrice != null && netPrice != null && netPrice < floorPrice;
    }

    /** Margin in percent, or null when it cannot be calculated. */
    public static Decimal calculateMarginPercent(Decimal netPrice, Decimal unitCost) {
        if (netPrice == null || netPrice == 0 || unitCost == null) {
            return null;
        }
        return (((netPrice - unitCost) / netPrice) * 100).setScale(2, System.RoundingMode.HALF_UP);
    }
}
