import SwiftUI
#if os(iOS)
import UIKit
#endif

/// One level on the provider dashboard navigation stack (replaces opaque `NavigationPath` pushes).
enum ProviderShellScreen: Hashable {
    case route(ProviderShellRoute)
    case booking(SimpleBookingDTO)
}

enum ProviderShellNavigationDirection {
    case forward
    case backward
}

@MainActor
@Observable
final class ProviderShellNavigator {
    static let transitionDuration: TimeInterval = 0.25

    static var transitionAnimation: Animation {
        .easeInOut(duration: transitionDuration)
    }

    private(set) var stack: [ProviderShellScreen] = []
    private(set) var direction: ProviderShellNavigationDirection = .forward
    /// `0` = pushed layer off-screen trailing; `1` = fully covering the hub.
    private(set) var slideProgress: CGFloat = 0
    private(set) var isInteractiveDragging = false

    private var slideAnimationTask: Task<Void, Never>?

    /// Messages inbox → conversation trail (stored here so shell re-renders do not reset navigation).
    var messagesDetailPath: [Int] = []

    var isHub: Bool { stack.isEmpty && slideProgress < 0.01 && !isInteractiveDragging }
    var hubAcceptsTouches: Bool { stack.isEmpty && slideProgress < 0.01 && !isInteractiveDragging }

    private let appearance = ProviderShellNavigationAppearance.shared

    func slideOffsetX(containerWidth: CGFloat) -> CGFloat {
        (1 - slideProgress) * containerWidth
    }

    func pushRoute(_ route: ProviderShellRoute) {
        direction = .forward
        appearance.setContainerBackdrop(route.pushedBackdropStyle)
        stack.append(.route(route))
        beginSlideIn()
    }

    func pushBooking(_ booking: SimpleBookingDTO) {
        direction = .forward
        appearance.setContainerBackdrop(.shell)
        stack.append(.booking(booking))
        beginSlideIn()
    }

    func pop() {
        guard !stack.isEmpty else { return }
        direction = .backward
        beginSlideOut()
    }

    /// Horizontal drag distance (÷ screen width) required on release to pop — `0.20` ≈ 20% of the screen.
    /// Dragging back below this distance on release snaps the page open without popping.
    static let interactiveDismissSwipeFraction: CGFloat = 0.20

    static var interactiveSnapAnimation: Animation {
        .interactiveSpring(response: 0.38, dampingFraction: 0.86, blendDuration: 0.12)
    }

    /// Finger-driven slide while entering or exiting a pushed screen (`0` = hub visible, `1` = covered).
    func updateInteractiveDrag(translationX: CGFloat, containerWidth: CGFloat, anchorProgress: CGFloat) {
        guard !stack.isEmpty, containerWidth > 0 else { return }
        slideAnimationTask?.cancel()
        isInteractiveDragging = true
        let delta = translationX / containerWidth
        slideProgress = min(1, max(0, anchorProgress - delta))
    }

    func beginInteractiveDragIfNeeded() {
        guard !stack.isEmpty else { return }
        slideAnimationTask?.cancel()
        isInteractiveDragging = true
    }

    func finishInteractiveDrag(translationX: CGFloat, containerWidth: CGFloat) {
        guard !stack.isEmpty else {
            isInteractiveDragging = false
            return
        }

        isInteractiveDragging = false
        let swipeDistance = max(0, translationX) / max(containerWidth, 1)
        let shouldDismiss = swipeDistance >= Self.interactiveDismissSwipeFraction

        if shouldDismiss {
            direction = .backward
            withAnimation(Self.interactiveSnapAnimation) {
                slideProgress = 0
            }
            slideAnimationTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.transitionDuration))
                guard !Task.isCancelled else { return }
                if !stack.isEmpty {
                    stack.removeLast()
                }
                syncAppearanceAfterStackChange()
            }
        } else {
            direction = .forward
            withAnimation(Self.interactiveSnapAnimation) {
                slideProgress = 1
            }
        }
    }

    func popToHub() {
        guard !stack.isEmpty else { return }
        direction = .backward
        slideAnimationTask?.cancel()
        withAnimation(Self.transitionAnimation) {
            slideProgress = 0
        }
        slideAnimationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.transitionDuration))
            guard !Task.isCancelled else { return }
            stack.removeAll()
            appearance.clearContainerBackdropImmediately()
            syncMessagesDetailPath()
        }
    }

    func resetAndPushRoute(_ route: ProviderShellRoute) {
        slideAnimationTask?.cancel()
        stack.removeAll()
        slideProgress = 0
        syncMessagesDetailPath()
        pushRoute(route)
    }

    /// Opens Messages, optionally deep-linking into a conversation thread (push tap / in-app route).
    func openMessages(conversationId: Int? = nil) {
        if case .route(.messages) = stack.last {
            if let conversationId {
                focusMessagesConversation(conversationId)
            }
            return
        }

        resetAndPushRoute(.messages)
        if let conversationId {
            prepareConversationDeepLink(conversationId)
            messagesDetailPath = [conversationId]
        }
    }

    /// Ensures a push/deep-link lands on one conversation screen — never stacks duplicates.
    private func focusMessagesConversation(_ conversationId: Int) {
        prepareConversationDeepLink(conversationId)

        if messagesDetailPath.last == conversationId {
            NotificationCenter.default.post(
                name: .providerMessagingConversationShouldRefresh,
                object: nil,
                userInfo: ["conversationId": conversationId]
            )
            return
        }

        messagesDetailPath = [conversationId]
    }

    private func prepareConversationDeepLink(_ conversationId: Int) {
        ProviderConversationMessagesPrefetch.invalidate(conversationId: conversationId)
        ProviderConversationMessagesPrefetch.prefetch(conversationId: conversationId)
    }

    private func beginSlideIn() {
        slideAnimationTask?.cancel()
        isInteractiveDragging = false
        slideProgress = 0
        slideAnimationTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, !isInteractiveDragging else { return }
            withAnimation(Self.transitionAnimation) {
                slideProgress = 1
            }
        }
    }

    private func beginSlideOut() {
        slideAnimationTask?.cancel()
        isInteractiveDragging = false
        withAnimation(Self.transitionAnimation) {
            slideProgress = 0
        }
        slideAnimationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.transitionDuration))
            guard !Task.isCancelled else { return }
            if !stack.isEmpty {
                stack.removeLast()
            }
            syncAppearanceAfterStackChange()
        }
    }

    private func syncAppearanceAfterStackChange() {
        syncMessagesDetailPath()
        if stack.isEmpty {
            appearance.clearContainerBackdropImmediately()
            slideProgress = 0
        } else if let top = stack.last {
            // After popping a nested shell route, the revealed screen must stay fully on-screen.
            slideProgress = 1
            switch top {
            case .route(let route):
                appearance.setContainerBackdrop(route.pushedBackdropStyle)
            case .booking:
                appearance.setContainerBackdrop(.shell)
            }
        }
    }

    private func syncMessagesDetailPath() {
        guard case .route(.messages)? = stack.last else {
            messagesDetailPath = []
            return
        }
    }
}

#if os(iOS)
/// Tracks inner navigation inside the active shell overlay so edge-swipe defers to child stacks
/// (SwiftUI `navigationDestination`, Messages conversation pushes, etc.) before dismissing the shell.
@MainActor
@Observable
final class ProviderShellNavigationPopBridge {
    static let shared = ProviderShellNavigationPopBridge()

    /// SwiftUI `NavigationStack` wrapping the active shell route (Bookings → detail, etc.).
    private(set) weak var hostNavigationController: UINavigationController?
    private(set) var hostStackDepth = 1

    /// UIKit nav embedded in a route (Messages inbox → conversation).
    private(set) weak var embeddedNavigationController: UINavigationController?
    private(set) var embeddedStackDepth = 1

    /// SwiftUI `navigationDestination` pushes that UIKit depth tracking can miss (Bookings → detail).
    private(set) var registeredHostDestinationDepth = 0

    /// Transient holds (e.g. chart scrub) that must block the shell edge-swipe dismiss.
    private(set) var shellDismissGestureSuppressionCount = 0

    /// A SwiftUI destination (e.g. Bookings → detail) is currently presented on the shell host stack.
    var isHostDestinationPresented: Bool { registeredHostDestinationDepth > 0 }

    var canPopEmbeddedNavigation: Bool { embeddedStackDepth > 1 }

    /// When `true`, the shell edge-swipe and shell back control defer to inner navigation first.
    var shouldDeferShellDismissGesture: Bool {
        isHostDestinationPresented || canPopEmbeddedNavigation || shellDismissGestureSuppressionCount > 0
    }

    /// Legacy alias — prefer `shouldDeferShellDismissGesture` / `isHostDestinationPresented`.
    var canPopHostNavigation: Bool { isHostDestinationPresented }
    var canPopInner: Bool { shouldDeferShellDismissGesture }

    func registerHostDestination() {
        registeredHostDestinationDepth += 1
    }

    func unregisterHostDestination() {
        registeredHostDestinationDepth = max(0, registeredHostDestinationDepth - 1)
    }

    func setHostDestinationPresented(_ presented: Bool) {
        registeredHostDestinationDepth = presented ? 1 : 0
    }

    func resetHostDestinations() {
        registeredHostDestinationDepth = 0
    }

    func beginShellDismissGestureSuppression() {
        shellDismissGestureSuppressionCount += 1
    }

    func endShellDismissGestureSuppression() {
        shellDismissGestureSuppressionCount = max(0, shellDismissGestureSuppressionCount - 1)
    }

    func refreshHost(from navigationController: UINavigationController?) {
        guard let navigationController else { return }
        hostNavigationController = navigationController
        hostStackDepth = max(1, navigationController.viewControllers.count)
    }

    func refreshEmbedded(from navigationController: UINavigationController?) {
        guard let navigationController else { return }
        embeddedNavigationController = navigationController
        embeddedStackDepth = max(1, navigationController.viewControllers.count)
    }

    func bind(_ navigationController: UINavigationController?) {
        refreshEmbedded(from: navigationController)
    }

    func refresh(from navigationController: UINavigationController?) {
        refreshHost(from: navigationController)
    }

    func clearEmbeddedNavigation() {
        embeddedNavigationController = nil
        embeddedStackDepth = 1
    }

    func resetHostNavigation() {
        hostNavigationController = nil
        hostStackDepth = 1
        resetHostDestinations()
    }

    func popInnerIfPossible() -> Bool {
        if canPopEmbeddedNavigation, let nav = embeddedNavigationController {
            nav.popViewController(animated: true)
            DispatchQueue.main.async { [weak self] in
                self?.refreshEmbedded(from: nav)
            }
            return true
        }
        if hostStackDepth > 1, let nav = hostNavigationController {
            nav.popViewController(animated: true)
            DispatchQueue.main.async { [weak self] in
                self?.refreshHost(from: nav)
            }
            return true
        }
        return false
    }
}

/// Keeps host `NavigationStack` depth in sync when SwiftUI `navigationDestination` pushes
/// (e.g. Bookings → detail) — those do not always re-fire per-route appearance callbacks.
private struct ProviderShellNavigationDepthTracker: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        TrackerViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        (uiViewController as? TrackerViewController)?.trackDepth()
    }

    final class TrackerViewController: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            trackDepth()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            trackDepth()
        }

        func trackDepth() {
            guard let nav = navigationController else { return }
            ProviderShellNavigationPopBridge.shared.refreshHost(from: nav)
        }
    }
}

extension View {
    func providerShellNavigationDepthTracking() -> some View {
        background {
            ProviderShellNavigationDepthTracker()
                .frame(width: 0, height: 0)
        }
    }

    /// Call on SwiftUI `navigationDestination` screens inside the shell host stack (e.g. Bookings → detail).
    func providerShellHostDestinationRegistration() -> some View {
        modifier(ProviderShellHostDestinationRegistrationModifier())
    }
}

private struct ProviderShellHostDestinationRegistrationModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear {
                ProviderShellNavigationPopBridge.shared.registerHostDestination()
            }
            .onDisappear {
                ProviderShellNavigationPopBridge.shared.unregisterHostDestination()
            }
    }
}
#endif

private struct ProviderShellBackToolbarModifier: ViewModifier {
    @Environment(ProviderShellNavigator.self) private var navigator
    #if os(iOS)
    @Environment(ProviderShellNavigationPopBridge.self) private var popBridge
    #endif

    func body(content: Content) -> some View {
        content
            .toolbar {
                #if os(iOS)
                if !popBridge.shouldDeferShellDismissGesture {
                    ToolbarItem(placement: .topBarLeading) {
                        shellBackButton
                    }
                }
                #else
                ToolbarItem(placement: .topBarLeading) {
                    shellBackButton
                }
                #endif
            }
    }

    private var shellBackButton: some View {
        Button(action: performBack) {
            Image(systemName: "chevron.backward")
                .fontWeight(.semibold)
        }
        .accessibilityLabel("Back")
    }

    private func performBack() {
        #if os(iOS)
        if ProviderShellNavigationPopBridge.shared.popInnerIfPossible() {
            return
        }
        #endif
        navigator.pop()
    }
}

#if os(iOS)
private struct ProviderShellInteractiveSlideModifier: ViewModifier {
    @Environment(ProviderShellNavigator.self) private var navigator
    @Environment(ProviderShellNavigationPopBridge.self) private var popBridge

    let containerWidth: CGFloat

    @State private var dragAnchorProgress: CGFloat?
    @State private var dragIsHorizontal: Bool?

    func body(content: Content) -> some View {
        // Keep a stable view tree — toggling between `content` and
        // `content.simultaneousGesture(...)` recreates embedded UIKit hosts (Messages inbox)
        // when conversation pushes bump `embeddedStackDepth`.
        content.simultaneousGesture(shellDragGesture)
    }

    private var shellDragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                guard !popBridge.shouldDeferShellDismissGesture else { return }
                guard containerWidth > 0, !navigator.stack.isEmpty else { return }

                if dragIsHorizontal == nil {
                    let horizontal = abs(value.translation.width)
                    let vertical = abs(value.translation.height)
                    guard horizontal > 4 || vertical > 4 else { return }
                    dragIsHorizontal = horizontal >= vertical * 0.85
                }

                guard dragIsHorizontal == true else { return }
                guard value.translation.width >= 0 else { return }

                if dragAnchorProgress == nil {
                    dragAnchorProgress = navigator.slideProgress
                    navigator.beginInteractiveDragIfNeeded()
                }

                navigator.updateInteractiveDrag(
                    translationX: value.translation.width,
                    containerWidth: containerWidth,
                    anchorProgress: dragAnchorProgress ?? navigator.slideProgress
                )
            }
            .onEnded { value in
                defer {
                    dragAnchorProgress = nil
                    dragIsHorizontal = nil
                }

                guard dragIsHorizontal == true else { return }
                guard !popBridge.shouldDeferShellDismissGesture else { return }
                guard !navigator.stack.isEmpty else { return }

                navigator.finishInteractiveDrag(
                    translationX: value.translation.width,
                    containerWidth: containerWidth
                )
            }
    }
}
#endif

private enum ProviderShellNavigatorOptionalEnvironmentKey: EnvironmentKey {
    static let defaultValue: ProviderShellNavigator? = nil
}

extension EnvironmentValues {
    var optionalProviderShellNavigator: ProviderShellNavigator? {
        get { self[ProviderShellNavigatorOptionalEnvironmentKey.self] }
        set { self[ProviderShellNavigatorOptionalEnvironmentKey.self] = newValue }
    }
}

extension View {
    func optionalProviderShellNavigatorEnvironment(_ navigator: ProviderShellNavigator?) -> some View {
        environment(\.optionalProviderShellNavigator, navigator)
    }

    func providerShellBackToolbar() -> some View {
        modifier(ProviderShellBackToolbarModifier())
    }

    func providerShellInteractiveSlide(containerWidth: CGFloat) -> some View {
        #if os(iOS)
        modifier(ProviderShellInteractiveSlideModifier(containerWidth: containerWidth))
        #else
        self
        #endif
    }
}
