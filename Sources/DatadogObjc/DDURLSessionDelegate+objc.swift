/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import Datadog

@objc
open class DDNSURLSessionDelegate: NSObject, URLSessionTaskDelegate, DDURLSessionDelegateProviding {
    public let delegate: DDURLSessionDelegate

    @objc
    override public init() {
        self.delegate = DDURLSessionDelegate()
    }

    /// Automatically tracked hosts can be customized per instance with this initializer
    /// - Parameter additionalFirstPartyHosts: these hosts are tracked **in addition to** what was
    /// passed to `DatadogConfiguration.Builder` via `trackURLSession(firstPartyHosts:)`
    /// **NOTE:** If `trackURLSession(firstPartyHosts:)` is never called, automatic tracking will **not** take place
    @objc
    public init(additionalFirstPartyHosts: Set<String>) {
        self.delegate = DDURLSessionDelegate(additionalFirstPartyHosts: additionalFirstPartyHosts)
    }

    @objc
    open func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        delegate.urlSession(session, task: task, didFinishCollecting: metrics)
    }

    @objc
    open func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        delegate.urlSession(session, task: task, didCompleteWithError: error)
    }
}
