#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Volt Core - Test Suite${NC}"
echo -e "${BLUE}========================================${NC}"

# Track test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test 1: Port Interface Tests
echo -e "\n${YELLOW}[1/3] Running Effects Port Interface Tests...${NC}"
if zig test src/ports/effects_test.zig > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Port interface tests passed${NC}"
    ((PASSED_TESTS++))
else
    echo -e "${RED}✗ Port interface tests failed${NC}"
    ((FAILED_TESTS++))
    zig test src/ports/effects_test.zig
fi
((TOTAL_TESTS++))

# Test 2: Build all
echo -e "\n${YELLOW}[2/3] Building project...${NC}"
if zig build > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Build successful${NC}"
    ((PASSED_TESTS++))
else
    echo -e "${RED}✗ Build failed${NC}"
    ((FAILED_TESTS++))
    zig build
fi
((TOTAL_TESTS++))

# Test 3: Run via zig build test
echo -e "\n${YELLOW}[3/3] Running zig build test...${NC}"
if zig build test > /dev/null 2>&1; then
    echo -e "${GREEN}✓ zig build test passed${NC}"
    ((PASSED_TESTS++))
else
    echo -e "${RED}✗ zig build test failed${NC}"
    ((FAILED_TESTS++))
fi
((TOTAL_TESTS++))

# Summary
echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}   Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Total Tests: ${TOTAL_TESTS}"
echo -e "Passed: ${GREEN}${PASSED_TESTS}${NC}"
echo -e "Failed: ${RED}${FAILED_TESTS}${NC}"

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "\n${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "\n${RED}✗ Some tests failed${NC}"
    exit 1
fi
