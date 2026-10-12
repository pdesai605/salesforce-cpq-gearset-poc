trigger DealDeskQuoteTrigger on SBQQ__Quote__c(before insert, before update) {
    QuoteTriggerHandler.handle(Trigger.operationType, Trigger.new, Trigger.oldMap);
}
