import { createElement } from 'lwc';
import DealDeskPanel, { riskBand } from 'c/dealDeskPanel';
import getSummary from '@salesforce/apex/DealDeskController.getSummary';
import updateApprovalStatus from '@salesforce/apex/DealDeskController.updateApprovalStatus';

jest.mock(
    '@salesforce/apex/DealDeskController.getSummary',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

jest.mock('@salesforce/apex/DealDeskController.updateApprovalStatus', () => ({ default: jest.fn() }), {
    virtual: true
});

const SUMMARY = {
    quoteId: 'a0q000000000001AAA',
    quoteName: 'Q-00042',
    discountPercent: 32.5,
    riskScore: 80,
    tier: 'Executive',
    requiresApproval: true,
    approvalStatus: 'Pending',
    belowFloorLines: 1,
    notes: '',
    canApprove: true,
    lines: [
        {
            id: 'a0r000000000001AAA',
            productName: 'Nimbus Core Licence',
            quantity: 250,
            netPrice: 80,
            floorPrice: 90,
            belowFloor: true,
            marginPercent: 37.5
        },
        {
            id: 'a0r000000000002AAA',
            productName: 'Premier Support',
            quantity: 1,
            netPrice: 12000,
            floorPrice: 10000,
            belowFloor: false,
            marginPercent: 55
        }
    ]
};

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function createPanel() {
    const element = createElement('c-deal-desk-panel', { is: DealDeskPanel });
    element.recordId = SUMMARY.quoteId;
    document.body.appendChild(element);
    return element;
}

describe('c-deal-desk-panel', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('maps risk scores to bands', () => {
        expect(riskBand(10).level).toBe('low');
        expect(riskBand(45).level).toBe('medium');
        expect(riskBand(95).level).toBe('high');
        expect(riskBand(undefined).level).toBe('low');
    });

    it('renders risk, tier, floor breaches and approval status', async () => {
        const element = createPanel();
        getSummary.emit(SUMMARY);
        await flushPromises();

        const root = element.shadowRoot;
        expect(root.querySelector('[data-id="risk-score"]').textContent).toContain('80');
        expect(root.querySelector('[data-id="risk-band"]').textContent).toBe('High risk');
        expect(root.querySelector('[data-id="tier"]').textContent).toBe('Executive');
        expect(root.querySelector('[data-id="below-floor"]').textContent).toBe('1 lines');
        expect(root.querySelector('[data-id="status"]').textContent).toBe('Pending');
        expect(root.querySelector('[data-id="gauge"]').className).toContain('gauge__fill_high');

        const table = root.querySelector('lightning-datatable');
        expect(table.data).toHaveLength(2);
        expect(table.data[0].floorLabel).toBe('Below floor');
        expect(table.data[1].floorLabel).toBe('OK');
    });

    it('shows approve and reject buttons only to approvers', async () => {
        const element = createPanel();
        getSummary.emit({ ...SUMMARY, canApprove: false });
        await flushPromises();

        const root = element.shadowRoot;
        expect(root.querySelector('[data-id="approve"]')).toBeNull();
        expect(root.querySelector('[data-id="awaiting"]')).not.toBeNull();
    });

    it('saves an approval decision', async () => {
        updateApprovalStatus.mockResolvedValue();
        const element = createPanel();
        getSummary.emit(SUMMARY);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="approve"]').click();
        await flushPromises();

        expect(updateApprovalStatus).toHaveBeenCalledWith({
            quoteId: SUMMARY.quoteId,
            status: 'Approved',
            notes: ''
        });
    });

    it('shows an error when the summary cannot load', async () => {
        const element = createPanel();
        getSummary.error({ message: 'Insufficient access' });
        await flushPromises();

        expect(element.shadowRoot.querySelector('.error-message').textContent).toBe('Insufficient access');
    });
});
