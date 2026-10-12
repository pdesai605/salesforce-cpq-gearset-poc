/**
 * Single entry point for SBQQ__Quote__c trigger logic.
 * Keep the trigger thin; all logic lives in services.
 */
public with sharing class QuoteTriggerHandler {
    /** Set to true in data loads or tests to skip Deal Desk evaluation. */
    public static Boolean bypass = false;

    public static void handle(
        System.TriggerOperation operation,
        List<SBQQ__Quote__c> newList,
        Map<Id, SBQQ__Quote__c> oldMap
    ) {
        if (bypass) {
            return;
        }
        switch on operation {
            when BEFORE_INSERT, BEFORE_UPDATE {
                DealDeskService.evaluateQuotes(newList, oldMap);
            }
            when else {
                return;
            }
        }
    }
}
