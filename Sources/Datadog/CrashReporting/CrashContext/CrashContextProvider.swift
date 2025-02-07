/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// An interface for writing and reading  the `CrashContext`
internal protocol CrashContextProviderType: class {
    /// Returns current `CrashContext` value.
    var currentCrashContext: CrashContext { get }
    /// Notifies on `CrashContext` change.
    var onCrashContextChange: ((CrashContext) -> Void)? { set get }
}

/// Manages the `CrashContext` reads and writes in a thread-safe manner.
internal class CrashContextProvider: CrashContextProviderType {
    /// Queue for synchronizing `unsafeCrashContext` updates.
    private let queue: DispatchQueue
    /// Unsychronized `CrashContext`. The `queue` must be used to synchronize its mutation.
    private var unsafeCrashContext: CrashContext {
        willSet { onCrashContextChange?(newValue) }
    }

    /// Observes changes to a particular `Value` in the `CrashContext` and manages its updates.
    private struct ContextValueUpdater<Value>: ValueObserver {
        let queue: DispatchQueue
        let update: (Value) -> Void

        func onValueChanged(oldValue: Value, newValue: Value) {
            queue.async { update(newValue) }
        }
    }

    /// Updates `CrashContext` with last `TrackingConsent` information.
    private lazy var trackingConsentUpdater = ContextValueUpdater<TrackingConsent>(queue: queue) { newValue in
        self.unsafeCrashContext.lastTrackingConsent = newValue
    }

    /// Updates `CrashContext` with last `UserInfo` information.
    private lazy var userInfoUpdater = ContextValueUpdater<UserInfo>(queue: queue) { newValue in
        self.unsafeCrashContext.lastUserInfo = newValue
    }

    /// Updates `CrashContext` with last `NetworkConnectionInfo` information.
    private lazy var networkConnectionInfoUpdater = ContextValueUpdater<NetworkConnectionInfo?>(queue: queue) { newValue in
        self.unsafeCrashContext.lastNetworkConnectionInfo = newValue
    }

    /// Updates `CrashContext` with last `CarrierInfo` information.
    private lazy var carrierInfoUpdater = ContextValueUpdater<CarrierInfo?>(queue: queue) { newValue in
        self.unsafeCrashContext.lastCarrierInfo = newValue
    }

    /// Updates `CrashContext` with last `RUMViewEvent` information.
    private lazy var rumViewEventUpdater = ContextValueUpdater<RUMEvent<RUMViewEvent>?>(queue: queue) { newValue in
        self.unsafeCrashContext.lastRUMViewEvent = newValue
    }

    // MARK: - Initializer

    init(
        consentProvider: ConsentProvider,
        userInfoProvider: UserInfoProvider,
        networkConnectionInfoProvider: NetworkConnectionInfoProviderType,
        carrierInfoProvider: CarrierInfoProviderType,
        rumViewEventProvider: ValuePublisher<RUMEvent<RUMViewEvent>?>
    ) {
        self.queue = DispatchQueue(
            label: "com.datadoghq.crash-context",
            target: .global(qos: .utility)
        )
        // Set initial context
        self.unsafeCrashContext = CrashContext(
            lastTrackingConsent: consentProvider.currentValue,
            lastUserInfo: userInfoProvider.value,
            lastRUMViewEvent: nil,
            lastNetworkConnectionInfo: networkConnectionInfoProvider.current,
            lastCarrierInfo: carrierInfoProvider.current
        )

        // Subscribe for context updates
        consentProvider.subscribe(trackingConsentUpdater)
        userInfoProvider.subscribe(userInfoUpdater)
        networkConnectionInfoProvider.subscribe(networkConnectionInfoUpdater)
        carrierInfoProvider.subscribe(carrierInfoUpdater)
        rumViewEventProvider.subscribe(rumViewEventUpdater)
    }

    // MARK: - CrashContextProviderType

    var currentCrashContext: CrashContext {
        queue.sync { unsafeCrashContext }
    }

    var onCrashContextChange: ((CrashContext) -> Void)? = nil
}
