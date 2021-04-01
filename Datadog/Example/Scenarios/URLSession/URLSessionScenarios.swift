/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import Datadog
import DatadogObjc

/// Base scenario for `URLSession` and `NSURLSession` instrumentation.  It makes
/// both Swift and Objective-C tests share the same endpoints and SDK configuration.
///
/// This scenario presents two view controllers. First sends requests for first party resources, the second
/// calls third party endpoints.
@objc
class URLSessionBaseScenario: NSObject {
    /// If yes, instrumented endpoints are passed to `DDURLSessionDelegate`; otherwise, they are passed to `DatadogConfiguration.trackURLSession` method
    @objc
    let feedAdditionalFirstyPartyHosts: Bool

    /// The URL to custom GET resource, observed by Tracing auto instrumentation.
    @objc
    let customGETResourceURL: URL

    /// The `URLRequest` to custom POST resource,  observed by Tracing auto instrumentation.
    @objc
    let customPOSTRequest: URLRequest

    /// An unresolvable URL to fake resource DNS resolution error,  observed by Tracing auto instrumentation.
    @objc
    let badResourceURL: URL

    /// The `URLRequest` to fake 3rd party resource. As it's 3rd party, it won't be observed by Tracing auto instrumentation.
    @objc
    let thirdPartyRequest: URLRequest

    /// The `URL` to fake 3rd party resource. As it's 3rd party, it won't be observed by Tracing auto instrumentation.
    @objc
    let thirdPartyURL: URL

    override init() {
        feedAdditionalFirstyPartyHosts = Bool.random()
        if ProcessInfo.processInfo.arguments.contains("IS_RUNNING_UI_TESTS") {
            let serverMockConfiguration = Environment.serverMockConfiguration()!
            customGETResourceURL = serverMockConfiguration.instrumentedEndpoints[0]
            customPOSTRequest = {
                var request = URLRequest(url: serverMockConfiguration.instrumentedEndpoints[1])
                request.httpMethod = "POST"
                return request
            }()
            badResourceURL = serverMockConfiguration.instrumentedEndpoints[2]
            thirdPartyURL = serverMockConfiguration.instrumentedEndpoints[3]
            thirdPartyRequest = {
                var request = URLRequest(url: serverMockConfiguration.instrumentedEndpoints[4])
                request.httpMethod = "POST"
                return request
            }()
        } else {
            customGETResourceURL = URL(string: "https://status.datadoghq.com")!
            customPOSTRequest = {
                var request = URLRequest(url: URL(string: "https://status.datadoghq.com/bad/path")!)
                request.httpMethod = "POST"
                request.addValue("dataTaskWithRequest", forHTTPHeaderField: "creation-method")
                return request
            }()
            badResourceURL = URL(string: "https://foo.bar")!
            thirdPartyURL = URL(string: "https://www.bitrise.io")!
            thirdPartyRequest = {
                var request = URLRequest(url: URL(string: "https://www.bitrise.io/about")!)
                request.httpMethod = "POST"
                return request
            }()
        }
    }

    func configureSDK(builder: Datadog.Configuration.Builder) {
        if feedAdditionalFirstyPartyHosts {
            _ = builder.trackURLSession()
        } else {
            _ = builder.trackURLSession(
                firstPartyHosts: [customGETResourceURL.host!, customPOSTRequest.url!.host!, badResourceURL.host!]
            )
        }
    }

    func buildURLSession() -> URLSession {
        let delegate: DDURLSessionDelegate
        if feedAdditionalFirstyPartyHosts {
            delegate = DDURLSessionDelegate(
                additionalFirstPartyHosts: [
                    customGETResourceURL.host!,
                    customPOSTRequest.url!.host!,
                    badResourceURL.host!
                ]
            )
        } else {
            delegate = DDURLSessionDelegate()
        }
        return URLSession(
            configuration: .default,
            delegate: delegate,
            delegateQueue: nil
        )
    }

    @objc
    func buildNSURLSession() -> URLSession {
        let delegate: DDNSURLSessionDelegate
        if feedAdditionalFirstyPartyHosts {
            delegate = DDNSURLSessionDelegate(
                additionalFirstPartyHosts: [
                    customGETResourceURL.host!,
                    customPOSTRequest.url!.host!,
                    badResourceURL.host!
                ]
            )
        } else {
            delegate = DDNSURLSessionDelegate()
        }
        return URLSession(
            configuration: .default,
            delegate: delegate,
            delegateQueue: nil
        )
    }
}
