import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getSummary from '@salesforce/apex/DealDeskController.getSummary';
import updateApprovalStatus from '@salesforce/apex/DealDeskController.updateApprovalStatus';

const LINE_COLUMNS = [
    { label: 'Product', fieldName: 'productName', wrapText: true },
    { label: 'Qty', fieldName: 'quantity', type: 'number', initialWidth: 70 },
    {
        label: 'Net Unit Price',
        fieldName: 'netPrice',
        type: 'currency',
        cellAttributes: { class: { fieldName: 'priceClass' } }
    },
    { label: 'Floor', fieldName: 'floorPrice', type: 'currency' },
    {
        label: 'Margin',
        fieldName: 'marginRatio',
        type: 'percent',
        typeAttributes: { maximumFractionDigits: 1 }
    },
    {
        label: 'Floor Check',
        fieldName: 'floorLabel',
        cellAttributes: {
            iconName: { fieldName: 'floorIcon' },
            class: { fieldName: 'priceClass' }
        }
    }
];

const RISK_BANDS = [
    { max: 29, level: 'low', label: 'Low risk', css: 'band band_low' },
    { max: 59, level: 'medium', label: 'Medium risk', css: 'band band_medium' },
    { max: 100, level: 'high', label: 'High risk', css: 'band band_high' }
];

export function riskBand(score) {
    const value = Number(score) || 0;
    return RISK_BANDS.find((band) => value <= band.max) || RISK_BANDS[RISK_BANDS.length - 1];
}

export default class DealDeskPanel extends LightningElement {
    @api recordId;

    columns = LINE_COLUMNS;
    summary;
    error;
    notes = '';
    isSaving = false;
    wiredResult;

    @wire(getSummary, { quoteId: '$recordId' })
    wiredSummary(result) {
        this.wiredResult = result;
        if (result.data) {
            this.summary = result.data;
            this.notes = result.data.notes || '';
            this.error = undefined;
        } else if (result.error) {
            this.error = this.reduceError(result.error);
            this.summary = undefined;
        }
    }

    get isLoading() {
        return !this.summary && !this.error;
    }

    get riskScore() {
        return this.summary ? this.summary.riskScore || 0 : 0;
    }

    get band() {
        return riskBand(this.riskScore);
    }

    get gaugeClass() {
        return `gauge__fill gauge__fill_${this.band.level}`;
    }

    get gaugeStyle() {
        return `width: ${Math.min(100, Math.max(0, this.riskScore))}%;`;
    }

    get discountRatio() {
        return this.summary && this.summary.discountPercent != null ? this.summary.discountPercent / 100 : 0;
    }

    get tierLabel() {
        return this.summary && this.summary.tier ? this.summary.tier : 'Not evaluated';
    }

    get statusLabel() {
        return this.summary && this.summary.approvalStatus ? this.summary.approvalStatus : 'Not Required';
    }

    get statusClass() {
        const map = {
            Approved: 'status status_approved',
            Rejected: 'status status_rejected',
            Pending: 'status status_pending'
        };
        return map[this.statusLabel] || 'status';
    }

    get belowFloorLines() {
        return this.summary ? this.summary.belowFloorLines || 0 : 0;
    }

    get hasBelowFloorLines() {
        return this.belowFloorLines > 0;
    }

    get rows() {
        if (!this.summary || !this.summary.lines) {
            return [];
        }
        return this.summary.lines.map((line) => ({
            ...line,
            marginRatio: line.marginPercent != null ? line.marginPercent / 100 : null,
            floorLabel: line.belowFloor ? 'Below floor' : 'OK',
            floorIcon: line.belowFloor ? 'utility:warning' : 'utility:success',
            priceClass: line.belowFloor ? 'slds-text-color_error' : ''
        }));
    }

    get hasLines() {
        return this.rows.length > 0;
    }

    get showApprovalActions() {
        return Boolean(this.summary && this.summary.canApprove && this.summary.requiresApproval);
    }

    get showAwaitingMessage() {
        return Boolean(
            this.summary && !this.summary.canApprove && this.summary.requiresApproval && this.statusLabel === 'Pending'
        );
    }

    handleNotesChange(event) {
        this.notes = event.target.value;
    }

    handleApprove() {
        this.saveDecision('Approved');
    }

    handleReject() {
        this.saveDecision('Rejected');
    }

    async saveDecision(status) {
        this.isSaving = true;
        try {
            await updateApprovalStatus({ quoteId: this.recordId, status, notes: this.notes });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: `Quote ${status.toLowerCase()}`,
                    message: 'Deal Desk decision saved.',
                    variant: status === 'Approved' ? 'success' : 'warning'
                })
            );
            await refreshApex(this.wiredResult);
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        } catch (err) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could not save decision',
                    message: this.reduceError(err),
                    variant: 'error'
                })
            );
        } finally {
            this.isSaving = false;
        }
    }

    reduceError(err) {
        if (!err) {
            return 'Unknown error';
        }
        if (err.body && err.body.message) {
            return err.body.message;
        }
        return err.message || 'Unknown error';
    }
}
