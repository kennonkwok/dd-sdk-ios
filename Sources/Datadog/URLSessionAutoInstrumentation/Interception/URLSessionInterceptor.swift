/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal protocol URLSessionInterceptorType: class {
    func modify(request: URLRequest, session: URLSession?) -> URLRequest
    func taskCreated(task: URLSessionTask, session: URLSession?)
    func taskMetricsCollected(task: URLSessionTask, metrics: URLSessionTaskMetrics)
    func taskCompleted(task: URLSessionTask, error: Error?)
}

/// An object performing interception of requests sent with `URLSession`.
public class URLSessionInterceptor: URLSessionInterceptorType {
    public static var shared: URLSessionInterceptor? {
        URLSessionAutoInstrumentation.instance?.interceptor
    }

    /// Filters first party `URLs` defined by the user.
    private let defaultFirstPartyURLsFilter: FirstPartyURLsFilter
    /// Filters internal `URLs` used by the SDK.
    private let internalURLsFilter: InternalURLsFilter
    /// Handles resources interception.
    /// Depending on which instrumentation is enabled, this can be either RUM or Tracing handler sending respectively: RUM Resource or tracing Span.
    internal let handler: URLSessionInterceptionHandler
    /// Whether or not to inject tracing headers to intercepted 1st party requests.
    /// Set to `true` if Tracing instrumentation is enabled (no matter o RUM state).
    internal let injectTracingHeadersToFirstPartyRequests: Bool
    /// Additional header injected to intercepted 1st party requests.
    /// Set to `x-datadog-origin: rum` if both RUM and Tracing instrumentations are enabled and `nil` in all other cases.
    internal let additionalHeadersForFirstPartyRequests: [String: String]?

    // MARK: - Initialization

    convenience init(
        configuration: FeaturesConfiguration.URLSessionAutoInstrumentation,
        dateProvider: DateProvider,
        appStateListener: AppStateListening
    ) {
        let handler: URLSessionInterceptionHandler

        if configuration.instrumentRUM {
            handler = URLSessionRUMResourcesHandler(dateProvider: dateProvider)
        } else {
            handler = URLSessionTracingHandler(appStateListener: appStateListener)
        }

        self.init(configuration: configuration, handler: handler, appStateListener: appStateListener)
    }

    init(
        configuration: FeaturesConfiguration.URLSessionAutoInstrumentation,
        handler: URLSessionInterceptionHandler,
        appStateListener: AppStateListening
    ) {
        self.defaultFirstPartyURLsFilter = FirstPartyURLsFilter(hosts: configuration.userDefinedFirstPartyHosts)
        self.internalURLsFilter = InternalURLsFilter(urls: configuration.sdkInternalURLs)
        self.handler = handler

        if configuration.instrumentTracing {
            self.injectTracingHeadersToFirstPartyRequests = true

            if configuration.instrumentRUM {
                // If RUM instrumentation is enabled, additional `x-datadog-origin: rum` header is injected to the user request,
                // so that user's backend instrumentation can further process it and count on RUM quota.
                self.additionalHeadersForFirstPartyRequests = [
                    TracingHTTPHeaders.originField: TracingHTTPHeaders.rumOriginValue
                ]
            } else {
                self.additionalHeadersForFirstPartyRequests = nil
            }
        } else {
            self.injectTracingHeadersToFirstPartyRequests = false
            self.additionalHeadersForFirstPartyRequests = nil
        }
    }

    /// An internal queue for synchronising the access to `interceptionByTask`.
    private let queue = DispatchQueue(label: "com.datadoghq.URLSessionInterceptor", target: .global(qos: .utility))
    /// Maps `URLSessionTask` to its `TaskInterception` object.
    private var interceptionByTask: [URLSessionTask: TaskInterception] = [:]

    // MARK: - Public

    /// Intercepts given `URLRequest` before it is sent.
    /// If Tracing feature is enabled and first party hosts are configured in `Datadog.Configuration`, this method will
    /// modify the `request` by adding Datadog trace propagation headers. This will enable end-to-end trace propagation
    /// from the client application to backend services instrumented with Datadog agents.
    /// - Parameter request: input request.
    /// - Returns: modified input requests. The modified request may contain additional Datadog headers.
    public func modify(request: URLRequest, session: URLSession? = nil) -> URLRequest {
        guard !internalURLsFilter.isInternal(url: request.url) else {
            return request
        }
        let isFirstPartyRequest = isFirstParty(request: request, for: session)
        if injectTracingHeadersToFirstPartyRequests && isFirstPartyRequest {
            return injectSpanContext(into: request)
        }
        return request
    }

    /// Notifies the `URLSessionTask` creation.
    /// This method should be called as soon as the task was created.
    /// - Parameter task: the task object obtained from `URLSession`.
    public func taskCreated(task: URLSessionTask, session: URLSession? = nil) {
        guard let request = task.originalRequest,
              !internalURLsFilter.isInternal(url: request.url) else {
            return
        }
        queue.async {
            let isFirstPartyRequest = self.isFirstParty(request: request, for: session)
            let interception = TaskInterception(
                request: request,
                isFirstParty: isFirstPartyRequest
            )
            self.interceptionByTask[task] = interception

            if let spanContext = self.extractSpanContext(from: request) {
                interception.register(spanContext: spanContext)
            }

            self.handler.notify_taskInterceptionStarted(interception: interception)
        }
    }

    /// Notifies the `URLSessionTask` metrics collection.
    /// This method should be called as soon as the task metrics were received by `URLSessionDelegate`.
    /// - Parameters:
    ///   - task: task receiving metrics.
    ///   - metrics: metrics object delivered to `URLSessionDelegate`.
    public func taskMetricsCollected(task: URLSessionTask, metrics: URLSessionTaskMetrics) {
        guard !internalURLsFilter.isInternal(url: task.originalRequest?.url) else {
            return
        }

        queue.async {
            guard let interception = self.interceptionByTask[task] else {
                return
            }

            interception.register(
                metrics: ResourceMetrics(taskMetrics: metrics)
            )

            if interception.isDone {
                self.finishInterception(task: task, interception: interception)
            }
        }
    }

    /// Notifies the `URLSessionTask` completion.
    /// This method should be called as soon as the task was completed.
    /// - Parameter task: the task object obtained from `URLSession`.
    /// - Parameter error: optional `Error` if the task completed with error.
    public func taskCompleted(task: URLSessionTask, error: Error?) {
        guard !internalURLsFilter.isInternal(url: task.originalRequest?.url) else {
            return
        }

        queue.async {
            guard let interception = self.interceptionByTask[task] else {
                return
            }

            interception.register(
                completion: ResourceCompletion(response: task.response, error: error)
            )

            if interception.isDone {
                self.finishInterception(task: task, interception: interception)
            }
        }
    }

    // MARK: - Private

    private func isFirstParty(request: URLRequest, for session: URLSession?) -> Bool {
        let delegateProvider = session?.delegate as? DDURLSessionDelegateProviding
        let delegateURLFilter = delegateProvider?.delegate.firstPartyURLsFilter
        let isFirstPartyForDelegate = (delegateURLFilter?.isFirstParty(url: request.url)) ?? false
        let isFirstPartyForInterceptor = self.defaultFirstPartyURLsFilter.isFirstParty(url: request.url)
        return isFirstPartyForDelegate || isFirstPartyForInterceptor
    }

    private func finishInterception(task: URLSessionTask, interception: TaskInterception) {
        interceptionByTask[task] = nil
        handler.notify_taskInterceptionCompleted(interception: interception)
    }

    // MARK: - SpanContext Injection & Extraction

    private func injectSpanContext(into firstPartyRequest: URLRequest) -> URLRequest {
        guard let tracer = Global.sharedTracer as? Tracer else {
            return firstPartyRequest
        }

        let writer = HTTPHeadersWriter()
        let spanContext = tracer.createSpanContext()

        tracer.inject(spanContext: spanContext, writer: writer)

        var newRequest = firstPartyRequest
        writer.tracePropagationHTTPHeaders.forEach { field, value in
            newRequest.setValue(value, forHTTPHeaderField: field)
        }

        additionalHeadersForFirstPartyRequests?.forEach { field, value in
            newRequest.setValue(value, forHTTPHeaderField: field)
        }

        return newRequest
    }

    private func extractSpanContext(from request: URLRequest) -> DDSpanContext? {
        guard let tracer = Global.sharedTracer as? Tracer,
              let headers = request.allHTTPHeaderFields else {
            return nil
        }

        let reader = HTTPHeadersReader(httpHeaderFields: headers)
        return tracer.extract(reader: reader) as? DDSpanContext
    }
}
