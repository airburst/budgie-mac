import Testing
@testable import BudgieMacKit

@Test("Clean names", arguments: [
    ("Joint Account", "Joint Account"),
    ("  Joint   Account \n", "Joint Account"),
    ("", "New Account"),
    ("   ", "New Account"),
])
func cleans(_ input: String, expected: String) {
    #expect(AccountName.clean(input) == expected)
}
