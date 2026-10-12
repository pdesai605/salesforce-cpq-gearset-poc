const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    modulePathIgnorePatterns: ['<rootDir>/.localdevserver'],
    coverageThreshold: {
        global: { branches: 60, functions: 75, lines: 75, statements: 75 }
    }
};
