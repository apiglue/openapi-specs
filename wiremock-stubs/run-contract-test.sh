#!/bin/zsh

#
# Integration test script for Contacts API WireMock stubs
# 
# This script makes curl calls to verify all WireMock mappings work correctly
# against the contacts-api.json OpenAPI specification.
#
# Prerequisites:
#   - WireMock standalone running on localhost:8080
#   - Start with: java -jar wiremock-standalone-3.9.1.jar --root-dir ./wiremock-stubs --global-response-templating
#
# Usage: ./run-tests.sh [wiremock-url]
#   Default URL: http://localhost:8080
#

set -e

# Configuration
WIREMOCK_URL="${1:-http://localhost:4010}"
BASE_PATH="/v1"
PASSED=0
FAILED=0
TOTAL=0

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Test UUIDs
VALID_CONTACT_ID="a1b2c3d4-e5f6-7890-ab12-cd34ef567890"
NOT_FOUND_CONTACT_ID="00000000-0000-0000-0000-000000000000"

# Helper functions
print_header() {
    echo ""
    echo "${BOLD}${BLUE}=== $1 ===${NC}"
    echo ""
}

print_test() {
    echo -n "  Testing: $1 ... "
}

pass() {
    echo "${GREEN}✓ PASSED${NC}"
    PASSED=$((PASSED + 1))
    TOTAL=$((TOTAL + 1))
}

fail() {
    echo "${RED}✗ FAILED${NC}"
    echo "    ${RED}Expected: $1${NC}"
    echo "    ${RED}Got: $2${NC}"
    FAILED=$((FAILED + 1))
    TOTAL=$((TOTAL + 1))
}

warn() {
    echo "${YELLOW}⚠ WARNING: $1${NC}"
}

# Check if WireMock is running
check_wiremock() {
    print_header "Checking WireMock availability"
    
    if curl -s --connect-timeout 5 "${WIREMOCK_URL}/__admin" > /dev/null 2>&1; then
        echo "  ${GREEN}✓${NC} WireMock is running at ${WIREMOCK_URL}"
        return 0
    else
        echo "  ${RED}✗${NC} WireMock is not running at ${WIREMOCK_URL}"
        echo ""
        echo "  Please start WireMock with:"
        echo "    java -jar wiremock-standalone-3.9.1.jar --root-dir ./wiremock-stubs --global-response-templating"
        echo ""
        exit 1
    fi
}

# Test: GET /contacts - List all contacts
test_get_contacts() {
    print_test "GET ${BASE_PATH}/contacts"
    
    response=$(curl -s -w "\n%{http_code}" "${WIREMOCK_URL}${BASE_PATH}/contacts")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [[ "$http_code" == "200" ]]; then
        # Verify response contains expected structure
        if echo "$body" | grep -q '"data"' && echo "$body" | grep -q '"pagination"'; then
            pass
        else
            fail "Response with data and pagination" "Missing expected fields"
        fi
    else
        fail "HTTP 200" "HTTP $http_code"
    fi
}

# Test: GET /contacts with query parameters
test_get_contacts_with_params() {
    print_test "GET ${BASE_PATH}/contacts?page=1&limit=10"
    
    response=$(curl -s -w "\n%{http_code}" "${WIREMOCK_URL}${BASE_PATH}/contacts?page=1&limit=10")
    http_code=$(echo "$response" | tail -n1)
    
    if [[ "$http_code" == "200" ]]; then
        pass
    else
        fail "HTTP 200" "HTTP $http_code"
    fi
}

# Test: POST /contacts - Create a new contact
test_post_contacts() {
    print_test "POST ${BASE_PATH}/contacts"
    
    request_body='{
        "firstName": "Test",
        "lastName": "User",
        "email": "test.user@example.com"
    }'
    
    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$request_body" \
        "${WIREMOCK_URL}${BASE_PATH}/contacts")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [[ "$http_code" == "201" ]]; then
        # Verify response contains required fields
        if echo "$body" | grep -q '"id"' && echo "$body" | grep -q '"firstName"'; then
            pass
        else
            fail "Response with id and firstName" "Missing expected fields"
        fi
    else
        fail "HTTP 201" "HTTP $http_code"
    fi
}

# Test: POST /contacts - Bad request (missing email)
test_post_contacts_bad_request() {
    print_test "POST ${BASE_PATH}/contacts (missing email - expect 400)"
    
    request_body='{
        "firstName": "Test",
        "lastName": "User"
    }'
    
    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$request_body" \
        "${WIREMOCK_URL}${BASE_PATH}/contacts")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [[ "$http_code" == "400" ]]; then
        # Verify error response structure
        if echo "$body" | grep -q '"error"' && echo "$body" | grep -q '"code"'; then
            pass
        else
            fail "Error response with code" "Missing expected error fields"
        fi
    else
        fail "HTTP 400" "HTTP $http_code"
    fi
}

# Test: GET /contacts/{ContactId} - Get contact by ID
test_get_contact_by_id() {
    print_test "GET ${BASE_PATH}/contacts/${VALID_CONTACT_ID}"
    
    response=$(curl -s -w "\n%{http_code}" "${WIREMOCK_URL}${BASE_PATH}/contacts/${VALID_CONTACT_ID}")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [[ "$http_code" == "200" ]]; then
        # Verify response contains required Contact fields
        if echo "$body" | grep -q '"id"' && \
           echo "$body" | grep -q '"firstName"' && \
           echo "$body" | grep -q '"lastName"' && \
           echo "$body" | grep -q '"email"'; then
            pass
        else
            fail "Contact with id, firstName, lastName, email" "Missing required fields"
        fi
    else
        fail "HTTP 200" "HTTP $http_code"
    fi
}

# Test: GET /contacts/{ContactId} - Contact not found
test_get_contact_not_found() {
    print_test "GET ${BASE_PATH}/contacts/${NOT_FOUND_CONTACT_ID} (expect 404)"
    
    response=$(curl -s -w "\n%{http_code}" "${WIREMOCK_URL}${BASE_PATH}/contacts/${NOT_FOUND_CONTACT_ID}")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [[ "$http_code" == "404" ]]; then
        # Verify error response structure
        if echo "$body" | grep -q '"error"'; then
            pass
        else
            fail "Error response" "Missing error object"
        fi
    else
        fail "HTTP 404" "HTTP $http_code"
    fi
}

# Test: PUT /contacts/{ContactId} - Update contact
test_put_contact() {
    print_test "PUT ${BASE_PATH}/contacts/${VALID_CONTACT_ID}"
    
    request_body='{
        "firstName": "Updated",
        "lastName": "Contact",
        "email": "updated.contact@example.com"
    }'
    
    response=$(curl -s -w "\n%{http_code}" \
        -X PUT \
        -H "Content-Type: application/json" \
        -d "$request_body" \
        "${WIREMOCK_URL}${BASE_PATH}/contacts/${VALID_CONTACT_ID}")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [[ "$http_code" == "200" ]]; then
        # Verify response contains required Contact fields
        if echo "$body" | grep -q '"id"' && echo "$body" | grep -q '"firstName"'; then
            pass
        else
            fail "Updated contact response" "Missing expected fields"
        fi
    else
        fail "HTTP 200" "HTTP $http_code"
    fi
}

# Test: DELETE /contacts/{ContactId} - Delete contact
test_delete_contact() {
    print_test "DELETE ${BASE_PATH}/contacts/${VALID_CONTACT_ID}"
    
    response=$(curl -s -w "\n%{http_code}" \
        -X DELETE \
        "${WIREMOCK_URL}${BASE_PATH}/contacts/${VALID_CONTACT_ID}")
    http_code=$(echo "$response" | tail -n1)
    
    if [[ "$http_code" == "204" ]]; then
        pass
    else
        fail "HTTP 204" "HTTP $http_code"
    fi
}

# Test: GET /contacts/{ContactId}/addresses - Get contact addresses
test_get_contact_addresses() {
    print_test "GET ${BASE_PATH}/contacts/${VALID_CONTACT_ID}/addresses"
    
    response=$(curl -s -w "\n%{http_code}" "${WIREMOCK_URL}${BASE_PATH}/contacts/${VALID_CONTACT_ID}/addresses")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [[ "$http_code" == "200" ]]; then
        # Verify response is an array with address objects
        if echo "$body" | grep -q '"city"' && echo "$body" | grep -q '"street"'; then
            pass
        else
            fail "Array of addresses" "Missing expected address fields"
        fi
    else
        fail "HTTP 200" "HTTP $http_code"
    fi
}

# Test: Verify Content-Type headers
test_content_type_headers() {
    print_test "Response Content-Type header"
    
    content_type=$(curl -s -I "${WIREMOCK_URL}${BASE_PATH}/contacts" | grep -i "content-type" | tr -d '\r')
    
    if echo "$content_type" | grep -qi "application/json"; then
        pass
    else
        fail "Content-Type: application/json" "$content_type"
    fi
}

# Main test runner
main() {
    echo ""
    echo "${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo "${BOLD}║     Contacts API - WireMock Integration Tests              ║${NC}"
    echo "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  Target: ${WIREMOCK_URL}"
    echo "  Date: $(date)"
    
    # Check WireMock is running
    check_wiremock
    
    # Run endpoint tests
    print_header "GET /contacts Tests"
    test_get_contacts
    test_get_contacts_with_params
    test_content_type_headers
    
    print_header "POST /contacts Tests"
    test_post_contacts
    test_post_contacts_bad_request
    
    print_header "GET /contacts/{ContactId} Tests"
    test_get_contact_by_id
    test_get_contact_not_found
    
    print_header "PUT /contacts/{ContactId} Tests"
    test_put_contact
    
    print_header "DELETE /contacts/{ContactId} Tests"
    test_delete_contact
    
    print_header "GET /contacts/{ContactId}/addresses Tests"
    test_get_contact_addresses
    
    # Print summary
    print_header "Test Summary"
    echo "  ${GREEN}Passed: ${PASSED}${NC}"
    echo "  ${RED}Failed: ${FAILED}${NC}"
    echo "  Total:  ${TOTAL}"
    echo ""
    
    if [[ $FAILED -eq 0 ]]; then
        echo "  ${GREEN}${BOLD}All tests passed! ✓${NC}"
        echo ""
        exit 0
    else
        echo "  ${RED}${BOLD}Some tests failed! ✗${NC}"
        echo ""
        exit 1
    fi
}

# Run main
main