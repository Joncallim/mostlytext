import FileCore
import Foundation
@testable import Preview
import Testing

// MARK: - Navigation policy

@Suite("HTMLPreviewNavigationPolicy")
struct HTMLPreviewNavigationPolicyTests {
    private let policy = HTMLPreviewPolicy.v1

    private func decision(
        _ rawURL: String,
        sameDocument: Bool = false,
        target: HTMLPreviewNavigationAction.Target = .mainFrame
    ) -> HTMLPreviewNavigationDecision {
        let url = URL(string: rawURL)
        let action = HTMLPreviewNavigationAction(
            url: url,
            isSameDocument: sameDocument,
            target: target
        )
        return HTMLPreviewNavigationPolicy.decision(for: action, policy: policy)
    }

    @Test func v1PolicyDisablesScriptsNetworkAndExternalCapabilities() {
        #expect(!policy.allowsContentJavaScript)
        #expect(!policy.allowsNetworkAccess)
        #expect(!policy.allowsExternalNavigation)
        #expect(!policy.allowsPopups)
        #expect(!policy.allowsDownloads)
        #expect(!policy.allowsResourceAccessOutsideDocumentRoot)
    }

    @Test func v1CSPBlocksScriptsNetworkFormsAndBase() {
        let csp = policy.contentSecurityPolicy
        #expect(csp.contains("default-src 'none'"))
        #expect(csp.contains("script-src 'none'"))
        #expect(csp.contains("connect-src 'none'"))
        #expect(csp.contains("form-action 'none'"))
        #expect(csp.contains("base-uri 'none'"))
        #expect(csp.contains("object-src 'none'"))
        // Local styles and resources remain renderable.
        #expect(csp.contains("style-src 'unsafe-inline' macdown-preview:"))
        #expect(csp.contains("img-src macdown-preview: data:"))
    }

    @Test func allowsPreviewSchemeMainFrameNavigation() {
        #expect(decision("macdown-preview://document/") == .allow)
        #expect(decision("macdown-preview://document/img.png") == .allow)
    }

    @Test func allowsSameDocumentFragmentNavigation() {
        #expect(decision("macdown-preview://document/#section", sameDocument: true) == .allow)
    }

    @Test func cancelsRemoteMainFrameNavigation() {
        for raw in [
            "https://evil.example/",
            "http://evil.example/",
            "ftp://evil.example/file",
            "ws://evil.example/",
        ] {
            #expect(decision(raw) == .cancel, "expected cancel for \(raw)")
        }
    }

    @Test func cancelsFileAndJavaScriptNavigation() {
        #expect(decision("file:///etc/passwd") == .cancel)
        #expect(decision("javascript:alert(1)") == .cancel)
    }

    @Test func cancelsDataReplacementNavigation() {
        // A top-level `data:` navigation would replace the hardened document
        // with payload that carries no injected CSP.
        #expect(decision("data:text/html,<script>") == .cancel)
    }

    @Test func cancelsDocumentDrivenOtherNavigationToRemoteScheme() {
        // WebKit reports `<meta http-equiv="refresh">` and `window.location`
        // navigations as `navigationType == .other`. The policy carries no
        // initiation hint at all: only the preview scheme is navigable, so
        // those navigations to remote schemes are cancelled by their URL.
        #expect(decision("https://evil.example/") == .cancel)
        #expect(decision("macdown-preview://document/") == .allow)
    }

    @Test func cancelsSubframeNavigationToRemoteScheme() {
        #expect(decision("https://evil.example/frame", target: .subframe) == .cancel)
        #expect(decision("macdown-preview://document/frame.html", target: .subframe) == .allow)
    }

    @Test func deniesPopups() {
        #expect(decision("macdown-preview://document/", target: .newWindow) == .cancel)
        #expect(decision("https://evil.example/", target: .newWindow) == .cancel)
        #expect(decision("macdown-preview://document/#section", sameDocument: true, target: .newWindow) == .cancel)
    }

    @Test func popupPermissionDoesNotFollowExternalNavigationPermission() {
        var external = policy
        external.allowsExternalNavigation = true
        let popup = HTMLPreviewNavigationAction(
            url: URL(string: "https://example.com/"), isSameDocument: false, target: .newWindow
        )
        #expect(HTMLPreviewNavigationPolicy.decision(for: popup, policy: external) == .cancel)
    }

    @Test func explicitlyPermittedPopupStillRespectsTheNavigationScheme() {
        var popupPolicy = policy
        popupPolicy.allowsPopups = true
        #expect(HTMLPreviewNavigationPolicy.decision(
            for: HTMLPreviewNavigationAction(
                url: URL(string: "macdown-preview://document/#section"), isSameDocument: true, target: .newWindow
            ), policy: popupPolicy
        ) == .allow)
        #expect(HTMLPreviewNavigationPolicy.decision(
            for: HTMLPreviewNavigationAction(
                url: URL(string: "https://example.com/"), isSameDocument: false, target: .newWindow
            ), policy: popupPolicy
        ) == .cancel)
    }

    @Test func allowsPreviewSchemeNavigationToNonRenderableMIME() {
        // Navigation policy alone allows the preview scheme regardless of the
        // resource type; download denial is a *response-layer* decision the
        // app host makes in `decidePolicyForNavigationResponse` (cancelled
        // when `canShowMIMEType` is false), which the policy layer cannot
        // express and package tests cannot exercise.
        #expect(decision("macdown-preview://document/report.pdf") == .allow)
    }

    @Test func allowsEverythingWhenExternalNavigationPermitted() {
        let permissive = HTMLPreviewPolicy(
            allowsContentJavaScript: true,
            contentSecurityPolicy: "",
            allowsNetworkAccess: true,
            allowsExternalNavigation: true,
            allowsPopups: true,
            allowsDownloads: true,
            allowsResourceAccessOutsideDocumentRoot: true
        )
        let action = HTMLPreviewNavigationAction(
            url: URL(string: "https://evil.example/"),
            isSameDocument: false,
            target: .mainFrame
        )
        #expect(HTMLPreviewNavigationPolicy.decision(for: action, policy: permissive) == .allow)
    }
}

// MARK: - Hardened document injection

@Suite("HTMLPreviewSecurity")
struct HTMLPreviewSecurityTests {
    @Test func injectsCSPIntoExistingHead() {
        let html = "<html><head><title>t</title></head><body>hi</body></html>"
        let out = PreviewSecurity.hardenedHTMLDocument(from: html)
        #expect(out.contains("Content-Security-Policy"))
        #expect(out.contains("default-src 'none'"))
        // The CSP must appear before the document's own <title>.
        let csp = out.range(of: "Content-Security-Policy")
        let title = out.range(of: "<title>")
        #expect(csp != nil)
        #expect(title != nil)
        if let csp, let title {
            #expect(csp.lowerBound < title.lowerBound)
        }
    }

    @Test func addsHeadWhenOnlyHTMLTagPresent() {
        let html = "<html><body>content</body></html>"
        let out = PreviewSecurity.hardenedHTMLDocument(from: html)
        #expect(out.contains("<html><head>"))
        #expect(out.contains("Content-Security-Policy"))
        #expect(out.contains("<body>content</body>"))
    }

    @Test func wrapsBareFragment() {
        let html = "<p>hello</p>"
        let out = PreviewSecurity.hardenedHTMLDocument(from: html)
        #expect(out.hasPrefix("<!DOCTYPE html>"))
        #expect(out.contains("Content-Security-Policy"))
        #expect(out.contains("<p>hello</p>"))
    }

    @Test func doesNotMatchHeaderTag() {
        // <header> must not be mistaken for <head>; a real <head> is added
        // after <html> instead.
        let html = "<html><body><header>menu</header></body></html>"
        let out = PreviewSecurity.hardenedHTMLDocument(from: html)
        #expect(out.contains("<html><head>"))
        #expect(out.contains("<header>menu</header>"))
        #expect(out.contains("Content-Security-Policy"))
    }

    @Test func matchesHeadWithAttributes() {
        let html = "<html><head class=\"x\"><title>t</title></head><body>hi</body></html>"
        let out = PreviewSecurity.hardenedHTMLDocument(from: html)
        // Injected right after the opening <head ...> tag.
        #expect(out.contains("<head class=\"x\"><meta http-equiv=\"Content-Security-Policy\""))
    }

    // MARK: Adversarial fixtures

    @Test func ignoresHeadInsideComment() {
        // The CSP must be injected into the real document head, not into a
        // comment that merely looks like markup.
        let html = "<!-- <head> --><html><head><title>t</title></head></html>"
        let out = PreviewSecurity.hardenedHTMLDocument(from: html)
        let csp = out.range(of: "Content-Security-Policy")
        let commentHead = out.range(of: "<!-- <head> -->")
        #expect(csp != nil)
        #expect(commentHead != nil)
        if let csp, let commentHead {
            #expect(csp.lowerBound > commentHead.upperBound)
        }
        #expect(out.range(of: "<head><meta http-equiv=\"Content-Security-Policy\"") != nil)
    }

    @Test func ignoresHeadInsideScriptRawtext() {
        let html = "<script>var s = \"<head>\";</script><html><head></head></html>"
        let out = PreviewSecurity.hardenedHTMLDocument(from: html)
        // The CSP lands in the real head, after the script element.
        let csp = out.range(of: "Content-Security-Policy")
        let script = out.range(of: "<script>var s = \"<head>\";</script>")
        #expect(csp != nil)
        #expect(script != nil)
        if let csp, let script {
            #expect(csp.lowerBound > script.upperBound)
        }
    }

    @Test func ignoresHeadInsideStyleRawtext() {
        let html = "<style>.x::before { content: \"<head>\"; }</style><html><head></head></html>"
        let out = PreviewSecurity.hardenedHTMLDocument(from: html)
        #expect(out.range(of: "Content-Security-Policy") != nil)
        let csp = out.range(of: "Content-Security-Policy")
        let style = out.range(of: "<style>.x::before { content: \"<head>\"; }</style>")
        if let csp, let style {
            #expect(csp.lowerBound > style.upperBound)
        }
    }

    @Test func ignoresHeadInsideQuotedAttributeValue() {
        let html = "<div title=\"<head>\"><html><head></head></html>"
        let out = PreviewSecurity.hardenedHTMLDocument(from: html)
        #expect(out.range(of: "<head><meta http-equiv=\"Content-Security-Policy\"") != nil)
    }

    @Test func ignoresHeadInsideCommentOnlyDocument() {
        // No real head exists: the whole fragment is wrapped in a hardened
        // document so the CSP still governs.
        let html = "<!-- <head> --><p>content</p>"
        let out = PreviewSecurity.hardenedHTMLDocument(from: html)
        #expect(out.hasPrefix("<!DOCTYPE html>"))
        #expect(out.contains("Content-Security-Policy"))
        #expect(out.contains("<p>content</p>"))
    }

    @Test func ignoresCaseVariantsInRawtextClose() {
        // Rawtext ends at a case-insensitive </SCRIPT>.
        let html = "<script>var s = \"<head>\";</SCRIPT><html><head></head></html>"
        let out = PreviewSecurity.hardenedHTMLDocument(from: html)
        #expect(out.range(of: "<head><meta http-equiv=\"Content-Security-Policy\"") != nil)
    }
}

// MARK: - Response headers (the enforcement boundary)

@Suite("HTMLPreviewResponseHeaders")
struct HTMLPreviewResponseHeadersTests {
    @Test func hardeningHeadersCarryTheCSP() {
        // The authoritative enforcement boundary: WebKit honors CSP headers
        // on custom-scheme responses, and markup cannot divert a header the
        // way a dead-context `<head>` can divert a meta injection.
        let headers = HTMLPreviewResponseHeaders.hardeningHeaders(for: .v1)
        let csp = headers[HTMLPreviewResponseHeaders.contentSecurityPolicy]
        #expect(csp != nil)
        #expect(csp?.contains("default-src 'none'") == true)
        #expect(csp?.contains("connect-src 'none'") == true)
        #expect(csp?.contains("frame-src macdown-preview:") == true)
    }

    @Test func hardeningHeadersReflectTheConfiguredPolicy() {
        // A host serving a permissive policy must receive that policy's CSP,
        // not the v1 constant.
        let permissive = HTMLPreviewPolicy(
            allowsContentJavaScript: true,
            contentSecurityPolicy: "default-src *",
            allowsNetworkAccess: true,
            allowsExternalNavigation: true,
            allowsPopups: true,
            allowsDownloads: true,
            allowsResourceAccessOutsideDocumentRoot: true
        )
        let headers = HTMLPreviewResponseHeaders.hardeningHeaders(for: permissive)
        #expect(headers[HTMLPreviewResponseHeaders.contentSecurityPolicy] == "default-src *")
    }

    @Test func headerNameIsTheStandardCSPHeader() {
        #expect(HTMLPreviewResponseHeaders.contentSecurityPolicy == "Content-Security-Policy")
    }
}
