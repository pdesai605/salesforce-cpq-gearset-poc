trigger DealDeskQuoteLineTrigger on SBQQ__QuoteLine__c(before insert, before update) {
    QuoteLineTriggerHandler.handle(Trigger.operationType, Trigger.new);
}
