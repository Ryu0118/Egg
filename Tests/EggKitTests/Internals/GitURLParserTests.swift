@testable import EggKit
import Testing

struct GitURLParserTests {
    private let parser = GitURLParser()

    @Test(arguments: ValidURLTestCase.allCases)
    func `parse valid URL`(_ testCase: ValidURLTestCase) {
        let result = parser.parse(testCase.input)
        #expect(result != nil)
        #expect(result?.original == testCase.input)
        #expect(result?.normalized == testCase.expectedNormalized)
    }

    @Test(arguments: InvalidURLTestCase.allCases)
    func `parse invalid URL`(_ testCase: InvalidURLTestCase) {
        let result = parser.parse(testCase.input)
        #expect(result == nil)
    }

    struct ValidURLTestCase: CustomTestStringConvertible {
        let description: String
        let input: String
        let expectedNormalized: String

        var testDescription: String {
            description
        }

        static let allCases: [ValidURLTestCase] = [
            // HTTPS URLs
            ValidURLTestCase(
                description: "HTTPS URL with .git suffix",
                input: "https://github.com/user/repo.git",
                expectedNormalized: "https://github.com/user/repo.git",
            ),
            ValidURLTestCase(
                description: "HTTPS URL without .git suffix",
                input: "https://github.com/user/repo",
                expectedNormalized: "https://github.com/user/repo",
            ),
            ValidURLTestCase(
                description: "HTTPS URL with nested path",
                input: "https://gitlab.com/group/subgroup/repo.git",
                expectedNormalized: "https://gitlab.com/group/subgroup/repo.git",
            ),
            ValidURLTestCase(
                description: "HTTP URL (non-secure)",
                input: "http://github.com/user/repo.git",
                expectedNormalized: "http://github.com/user/repo.git",
            ),

            // SSH URLs
            ValidURLTestCase(
                description: "SSH URL with .git suffix",
                input: "git@github.com:user/repo.git",
                expectedNormalized: "git@github.com:user/repo.git",
            ),
            ValidURLTestCase(
                description: "SSH URL without .git suffix",
                input: "git@github.com:user/repo",
                expectedNormalized: "git@github.com:user/repo",
            ),
            ValidURLTestCase(
                description: "SSH URL with nested path",
                input: "git@gitlab.com:group/subgroup/repo.git",
                expectedNormalized: "git@gitlab.com:group/subgroup/repo.git",
            ),
            ValidURLTestCase(
                description: "SSH URL with different host",
                input: "git@bitbucket.org:user/repo.git",
                expectedNormalized: "git@bitbucket.org:user/repo.git",
            ),

            // Git protocol URLs
            ValidURLTestCase(
                description: "Git protocol URL with .git suffix",
                input: "git://github.com/user/repo.git",
                expectedNormalized: "git://github.com/user/repo.git",
            ),
            ValidURLTestCase(
                description: "Git protocol URL without .git suffix",
                input: "git://github.com/user/repo",
                expectedNormalized: "git://github.com/user/repo",
            ),
            ValidURLTestCase(
                description: "file URL for local git fixture",
                input: "file:///tmp/egg-template-fixture.git",
                expectedNormalized: "file:///tmp/egg-template-fixture.git",
            ),

            // HTTPS URLs with authentication
            ValidURLTestCase(
                description: "HTTPS URL with access token (GitHub Actions)",
                input: "https://x-access-token:ghp_xxxxxxxxxxxx@github.com/user/repo.git",
                expectedNormalized: "https://x-access-token:ghp_xxxxxxxxxxxx@github.com/user/repo.git",
            ),
            ValidURLTestCase(
                description: "HTTPS URL with username and password",
                input: "https://username:password@github.com/user/repo.git",
                expectedNormalized: "https://username:password@github.com/user/repo.git",
            ),
            ValidURLTestCase(
                description: "HTTPS URL with token containing special chars",
                input: "https://x-access-token:ghs_ABC123xyz@github.com/user/repo.git",
                expectedNormalized: "https://x-access-token:ghs_ABC123xyz@github.com/user/repo.git",
            ),

            // URLs with special characters in path
            ValidURLTestCase(
                description: "URL with hyphen in repo name",
                input: "https://github.com/user/my-repo.git",
                expectedNormalized: "https://github.com/user/my-repo.git",
            ),
            ValidURLTestCase(
                description: "URL with underscore in repo name",
                input: "https://github.com/user/my_repo.git",
                expectedNormalized: "https://github.com/user/my_repo.git",
            ),
            ValidURLTestCase(
                description: "URL with dots in repo name",
                input: "https://github.com/user/my.repo.git",
                expectedNormalized: "https://github.com/user/my.repo.git",
            ),
        ]
    }

    struct InvalidURLTestCase: CustomTestStringConvertible {
        let description: String
        let input: String

        var testDescription: String {
            description
        }

        static let allCases: [InvalidURLTestCase] = [
            InvalidURLTestCase(
                description: "empty string",
                input: "",
            ),
            InvalidURLTestCase(
                description: "whitespace only",
                input: "   ",
            ),
            InvalidURLTestCase(
                description: "plain text",
                input: "not a url",
            ),
            InvalidURLTestCase(
                description: "missing host",
                input: "https:///repo.git",
            ),
            InvalidURLTestCase(
                description: "missing path",
                input: "https://github.com",
            ),
            InvalidURLTestCase(
                description: "invalid SSH format (missing colon)",
                input: "git@github.com/user/repo.git",
            ),
            InvalidURLTestCase(
                description: "ftp protocol",
                input: "ftp://github.com/user/repo.git",
            ),
        ]
    }
}
