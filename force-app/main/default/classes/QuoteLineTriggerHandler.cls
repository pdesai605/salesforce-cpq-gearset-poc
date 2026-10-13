/**
 * Single entry point for SBQQ__QuoteLine__c trigger logic.
 * Stamps floor price, below-floor flag and margin on every line.
 * The Below Floor flag rolls up to the quote, which re-scores the deal.
 */
public with sharing class QuoteLineTriggerHandler {
    /** Set to true in data loads or tests to skip floor pricing. */
    public static Boolean bypass = false;

    public static void handle(System.TriggerOperation operation, List<SBQQ__QuoteLine__c> newList) {
        if (bypass) {
            return;
        }
        switch on operation {
            when BEFORE_INSERT, BEFORE_UPDATE {
                applyFloorPricing(newList);
            }
            when else {
                return;
            }
        }
    }

    @SuppressWarnings('PMD.ApexCRUDViolation')
    public static void applyFloorPricing(List<SBQQ__QuoteLine__c> lines) {
        Set<Id> productIds = new Set<Id>();
        for (SBQQ__QuoteLine__c line : lines) {
            if (line.SBQQ__Product__c != null) {
                productIds.add(line.SBQQ__Product__c);
            }
        }

        Map<Id, Product2> products = new Map<Id, Product2>();
        if (!productIds.isEmpty()) {
            // System mode on purpose: margin must be calculated for every saved line,
            // including lines saved by users who cannot see product unit cost.
            products = new Map<Id, Product2>(
                [SELECT Id, Floor_Price__c, Unit_Cost__c FROM Product2 WHERE Id IN :productIds WITH SYSTEM_MODE]
            );
        }

        for (SBQQ__QuoteLine__c line : lines) {
            Product2 product = products.get(line.SBQQ__Product__c);
            Decimal floorPrice = product == null ? null : product.Floor_Price__c;
            Decimal unitCost = product == null ? null : product.Unit_Cost__c;

            line.Floor_Price__c = floorPrice;
            line.Below_Floor__c = FloorPricingService.isBelowFloor(line.SBQQ__NetPrice__c, floorPrice);
            line.Line_Margin_Percent__c = FloorPricingService.calculateMarginPercent(line.SBQQ__NetPrice__c, unitCost);
        }
    }
}
