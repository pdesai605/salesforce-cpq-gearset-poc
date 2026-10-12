// =============================================================================
// Seed the "Nimbus Cloud Platform" CPQ catalogue in the DEV org.
//
// Creates: 5 products + standard price book entries, a configurable bundle
// (features + options), a volume discount schedule, a price rule and a
// product (validation) rule.
//
// This is CPQ CONFIGURATION DATA, not metadata. In the demo, Gearset's CPQ
// deployment moves it from Dev to QA, UAT and Prod.
//
// Run:  sf apex run --file scripts/apex/seed-cpq-catalog.apex --target-org poc-dev
// Safe to re-run: it stops if the catalogue already exists.
// =============================================================================

if (![SELECT Id FROM Product2 WHERE ProductCode = 'NIMBUS-PLATFORM' LIMIT 1].isEmpty()) {
    System.debug(LoggingLevel.WARN, 'Nimbus catalogue already exists. Nothing to do.');
} else {
    Savepoint sp = Database.setSavepoint();
    try {
        Id standardPricebookId = [SELECT Id FROM Pricebook2 WHERE IsStandard = TRUE LIMIT 1].Id;

        // ---------------------------------------------------------------- Discount schedule
        SBQQ__DiscountSchedule__c seatVolume = new SBQQ__DiscountSchedule__c(
            Name = 'Nimbus Seat Volume',
            SBQQ__Type__c = 'Range',
            SBQQ__DiscountUnit__c = 'Percent'
        );
        insert seatVolume;

        insert new List<SBQQ__DiscountTier__c>{
            new SBQQ__DiscountTier__c(Name = '1-99 seats', SBQQ__Schedule__c = seatVolume.Id,
                SBQQ__LowerBound__c = 1, SBQQ__UpperBound__c = 100, SBQQ__Discount__c = 0),
            new SBQQ__DiscountTier__c(Name = '100-499 seats', SBQQ__Schedule__c = seatVolume.Id,
                SBQQ__LowerBound__c = 100, SBQQ__UpperBound__c = 500, SBQQ__Discount__c = 5),
            new SBQQ__DiscountTier__c(Name = '500+ seats', SBQQ__Schedule__c = seatVolume.Id,
                SBQQ__LowerBound__c = 500, SBQQ__Discount__c = 10)
        };

        // ---------------------------------------------------------------- Products
        Product2 platform = new Product2(
            Name = 'Nimbus Cloud Platform', ProductCode = 'NIMBUS-PLATFORM', Family = 'Software', IsActive = true,
            Description = 'Configurable platform bundle: licences, analytics and services.',
            SBQQ__ConfigurationType__c = 'Allowed', SBQQ__ConfigurationEvent__c = 'Always',
            SBQQ__PricingMethod__c = 'List'
        );
        Product2 core = new Product2(
            Name = 'Nimbus Core Licence', ProductCode = 'NIMBUS-CORE', Family = 'Software', IsActive = true,
            Description = 'Per-seat annual subscription.',
            SBQQ__PricingMethod__c = 'List', SBQQ__SubscriptionPricing__c = 'Fixed Price',
            SBQQ__SubscriptionTerm__c = 12, SBQQ__SubscriptionType__c = 'Renewable',
            SBQQ__DiscountSchedule__c = seatVolume.Id,
            Floor_Price__c = 90, Unit_Cost__c = 30
        );
        Product2 analytics = new Product2(
            Name = 'Nimbus Analytics Add-on', ProductCode = 'NIMBUS-ANALYTICS', Family = 'Software', IsActive = true,
            Description = 'Per-seat analytics subscription.',
            SBQQ__PricingMethod__c = 'List', SBQQ__SubscriptionPricing__c = 'Fixed Price',
            SBQQ__SubscriptionTerm__c = 12, SBQQ__SubscriptionType__c = 'Renewable',
            Floor_Price__c = 30, Unit_Cost__c = 12
        );
        Product2 support = new Product2(
            Name = 'Nimbus Premier Support', ProductCode = 'NIMBUS-SUPPORT-PREMIER', Family = 'Services', IsActive = true,
            Description = '24x7 support with a named technical account manager.',
            SBQQ__PricingMethod__c = 'List',
            Floor_Price__c = 12000, Unit_Cost__c = 6000
        );
        Product2 onboarding = new Product2(
            Name = 'Nimbus Onboarding Services', ProductCode = 'NIMBUS-ONBOARDING', Family = 'Services', IsActive = true,
            Description = 'Fixed-scope implementation and training. Free on 3-year deals (price rule).',
            SBQQ__PricingMethod__c = 'List',
            Unit_Cost__c = 4000
        );
        List<Product2> products = new List<Product2>{ platform, core, analytics, support, onboarding };
        insert products;

        Map<Id, Decimal> listPrices = new Map<Id, Decimal>{
            platform.Id => 0, core.Id => 120, analytics.Id => 40, support.Id => 15000, onboarding.Id => 8000
        };
        List<PricebookEntry> entries = new List<PricebookEntry>();
        for (Product2 p : products) {
            entries.add(new PricebookEntry(
                Pricebook2Id = standardPricebookId, Product2Id = p.Id, UnitPrice = listPrices.get(p.Id), IsActive = true
            ));
        }
        insert entries;

        // ---------------------------------------------------------------- Bundle structure
        SBQQ__ProductFeature__c licences = new SBQQ__ProductFeature__c(
            Name = 'Licences', SBQQ__ConfiguredSKU__c = platform.Id, SBQQ__Number__c = 10, SBQQ__MinOptionCount__c = 1
        );
        SBQQ__ProductFeature__c services = new SBQQ__ProductFeature__c(
            Name = 'Services', SBQQ__ConfiguredSKU__c = platform.Id, SBQQ__Number__c = 20
        );
        insert new List<SBQQ__ProductFeature__c>{ licences, services };

        insert new List<SBQQ__ProductOption__c>{
            new SBQQ__ProductOption__c(SBQQ__ConfiguredSKU__c = platform.Id, SBQQ__OptionalSKU__c = core.Id,
                SBQQ__Feature__c = licences.Id, SBQQ__Number__c = 10, SBQQ__Quantity__c = 100,
                SBQQ__QuantityEditable__c = true, SBQQ__Required__c = true, SBQQ__Selected__c = true,
                SBQQ__Type__c = 'Component'),
            new SBQQ__ProductOption__c(SBQQ__ConfiguredSKU__c = platform.Id, SBQQ__OptionalSKU__c = analytics.Id,
                SBQQ__Feature__c = licences.Id, SBQQ__Number__c = 20, SBQQ__Quantity__c = 100,
                SBQQ__QuantityEditable__c = true, SBQQ__Type__c = 'Component'),
            new SBQQ__ProductOption__c(SBQQ__ConfiguredSKU__c = platform.Id, SBQQ__OptionalSKU__c = support.Id,
                SBQQ__Feature__c = services.Id, SBQQ__Number__c = 30, SBQQ__Quantity__c = 1,
                SBQQ__Type__c = 'Component'),
            new SBQQ__ProductOption__c(SBQQ__ConfiguredSKU__c = platform.Id, SBQQ__OptionalSKU__c = onboarding.Id,
                SBQQ__Feature__c = services.Id, SBQQ__Number__c = 40, SBQQ__Quantity__c = 1,
                SBQQ__Selected__c = true, SBQQ__Type__c = 'Component')
        };

        // ---------------------------------------------------------------- Price rule
        // Free onboarding on 3-year (36+ month) deals.
        SBQQ__PriceRule__c freeOnboarding = new SBQQ__PriceRule__c(
            Name = 'Free Onboarding on 3-Year Deals', SBQQ__Active__c = true,
            SBQQ__TargetObject__c = 'Calculator', SBQQ__EvaluationEvent__c = 'On Calculate',
            SBQQ__ConditionsMet__c = 'All', SBQQ__EvaluationOrder__c = 10
        );
        insert freeOnboarding;
        insert new List<SBQQ__PriceCondition__c>{
            new SBQQ__PriceCondition__c(SBQQ__Rule__c = freeOnboarding.Id, SBQQ__Index__c = 1,
                SBQQ__Object__c = 'Quote Line', SBQQ__Field__c = 'SBQQ__ProductCode__c',
                SBQQ__Operator__c = 'equals', SBQQ__FilterType__c = 'Value', SBQQ__Value__c = 'NIMBUS-ONBOARDING'),
            new SBQQ__PriceCondition__c(SBQQ__Rule__c = freeOnboarding.Id, SBQQ__Index__c = 2,
                SBQQ__Object__c = 'Quote', SBQQ__Field__c = 'SBQQ__SubscriptionTerm__c',
                SBQQ__Operator__c = 'greater or equals', SBQQ__FilterType__c = 'Value', SBQQ__Value__c = '36')
        };
        insert new SBQQ__PriceAction__c(
            SBQQ__Rule__c = freeOnboarding.Id, SBQQ__Order__c = 1,
            SBQQ__Field__c = 'SBQQ__SpecialPrice__c', SBQQ__Value__c = '0'
        );

        // ---------------------------------------------------------------- Product (validation) rule
        SBQQ__ProductRule__c enterpriseAgreement = new SBQQ__ProductRule__c(
            Name = 'Enterprise Agreement Required Above 5,000 Seats', SBQQ__Active__c = true,
            SBQQ__Type__c = 'Validation', SBQQ__Scope__c = 'Quote', SBQQ__EvaluationEvent__c = 'Save',
            SBQQ__ConditionsMet__c = 'All', SBQQ__EvaluationOrder__c = 10,
            SBQQ__ErrorMessage__c = 'Deals above 5,000 seats must be contracted under an Enterprise Agreement. Contact the Deal Desk.'
        );
        insert enterpriseAgreement;
        insert new SBQQ__ErrorCondition__c(
            SBQQ__Rule__c = enterpriseAgreement.Id, SBQQ__Index__c = 1,
            SBQQ__TestedObject__c = 'Quote Line', SBQQ__TestedField__c = 'SBQQ__Quantity__c',
            SBQQ__Operator__c = 'greater than', SBQQ__FilterType__c = 'Value', SBQQ__FilterValue__c = '5000'
        );

        System.debug(LoggingLevel.INFO, 'Nimbus CPQ catalogue created: 5 products, 1 bundle, 1 discount schedule, 1 price rule, 1 product rule.');
    } catch (Exception e) {
        Database.rollback(sp);
        System.debug(LoggingLevel.ERROR, 'Seeding failed and was rolled back: ' + e.getMessage());
        throw e;
    }
}
