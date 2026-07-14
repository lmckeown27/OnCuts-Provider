import SwiftUI
#if os(iOS)
import UIKit
#endif

/// One level on the provider dashboard navigation stack (replaces opaque `NavigationPath` pushes).
enum ProviderShellScreen: Hashable {
    case route(ProviderShellRoute)
    case booking(SimpleBookingDTO)

    var overlayIdentity: String {
        switch self {
        case .route(let route):
            return "route-\(route)"
        case .booking(let booking):
            return "booking-\(booking.id)"
        }
    }
}

enum ProviderShellNavigationDirection {
    case forward
    case backward
}

@MainActor
@Observable
final class ProviderShellNavigator {
    static let transitionDuration: TimeInterval = 0.2

    static var transitionAnimation: Animation {
        .easeOut(duration: transitionDuration)
    }

    private(set) var stack: [ProviderShellScreen] = []
    /// Screen animating off-screen after the stack has already popped (keeps the hub responsive).
    private(set) var dismissingScreen: ProviderShellScreen?
    private(set) var direction: ProviderShellNavigationDirection = .forward
    /// `0` = pushed layer off-screen trailing; `1` = fully covering the hub.
    private(set) var slideProgress: CGFloat = 0
    private(set) var isInteractiveDragging = false

    private var slideAnimationTask: Task<Void, Never>?

    /// Messages inbox → conversation trail (stored here so shell re-renders do not reset navigation).
    var messagesDetailPath: [Int] = []

    var isHub: Bool {
        stack.isEmpty && dismissingScreen == nil && slideProgress < 0.01 && !isInteractiveDragging
    }

    var hubAcceptsTouches: Bool {
        guard !isInteractiveDragging, stack.isEmpty else { return false }
        if dismissingScreen != nil {
            return slideProgress < 0.05
        }
        return slideProgress < 0.01
    }

    /// Active pushed layer — includes a screen that is mid-dismiss animation.
    var overlayScreen: ProviderShellScreen? {
        stack.last ?? dismissingScreen
    }

    var isDismissingOverlay: Bool {
        dismissingScreen != nil && stack.isEmpty
    }

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
            commitSlideOut()
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
        guard let conversationId else { return }

        prepareConversationDeepLink(conversationId)
        // Defer path mutation to the next run loop so shell push + inner NavigationStack
        // destination do not both update in the same frame (NavigationRequestObserver warning).
        Task { @MainActor in
            await Task.yield()
            guard case .route(.messages)? = stack.last else { return }
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
        dismissingScreen = nil
        slideProgress = 0
        DispatchQueue.main.async { [self] in
            withAnimation(Self.transitionAnimation) {
                slideProgress = 1
            }
        }
    }

    private func beginSlideOut() {
        guard !stack.isEmpty else { return }
        direction = .backward
        animateSlideOut(exiting: stack.removeLast(), animation: Self.transitionAnimation)
    }

    private func commitSlideOut() {
        guard !stack.isEmpty else { return }
        direction = .backward
        animateSlideOut(exiting: stack.removeLast(), animation: Self.interactiveSnapAnimation)
    }

    private func animateSlideOut(exiting: ProviderShellScreen, animation: Animation) {
        slideAnimationTask?.cancel()
        isInteractiveDragging = false
        dismissingScreen = exiting
        withAnimation(animation) {
            slideProgress = 0
        }
        slideAnimationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.transitionDuration))
            guard !Task.isCancelled else { return }
            dismissingScreen = nil
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

    func body(content: Content) -> some View {
        // UIKit pan installs onto the host view so swipe-back works from scroll
        // content / labels (non-controls), matching Messages and other shell pages.
        // `simultaneousGesture` alone often loses to UIScrollView pans.
        content.background {
            ProviderShellInteractiveBackPanInstaller(
                containerWidth: containerWidth,
                navigator: navigator,
                popBridge: popBridge
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Attaches a shell back-pan to the nearest host view so horizontal swipes on
/// non-interactive content dismiss the pushed shell page.
private struct ProviderShellInteractiveBackPanInstaller: UIViewRepresentable {
    let containerWidth: CGFloat
    let navigator: ProviderShellNavigator
    let popBridge: ProviderShellNavigationPopBridge

    func makeCoordinator() -> Coordinator {
        Coordinator(navigator: navigator, popBridge: popBridge)
    }

    func makeUIView(context: Context) -> UIView {
        let probe = UIView(frame: .zero)
        probe.isUserInteractionEnabled = false
        probe.backgroundColor = .clear
        return probe
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.containerWidth = containerWidth
        context.coordinator.navigator = navigator
        context.coordinator.popBridge = popBridge
        context.coordinator.scheduleAttach(from: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var containerWidth: CGFloat = 0
        var navigator: ProviderShellNavigator
        var popBridge: ProviderShellNavigationPopBridge

        private weak var hostView: UIView?
        private weak var panRecognizer: UIPanGestureRecognizer?
        private var attachWorkItem: DispatchWorkItem?
        private var dragAnchorProgress: CGFloat?
        private var dragIsHorizontal: Bool?

        private static let recognizerName = "ProviderShellInteractiveBackPan"

        init(navigator: ProviderShellNavigator, popBridge: ProviderShellNavigationPopBridge) {
            self.navigator = navigator
            self.popBridge = popBridge
        }

        func scheduleAttach(from probe: UIView) {
            attachWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self, weak probe] in
                guard let self, let probe else { return }
                self.attachIfNeeded(from: probe)
            }
            attachWorkItem = work
            DispatchQueue.main.async(execute: work)
        }

        func teardown() {
            attachWorkItem?.cancel()
            attachWorkItem = nil
            detachPan()
            dragAnchorProgress = nil
            dragIsHorizontal = nil
        }

        private func detachPan() {
            if let panRecognizer, let hostView {
                hostView.removeGestureRecognizer(panRecognizer)
            }
            panRecognizer = nil
            hostView = nil
        }

        private func attachIfNeeded(from probe: UIView) {
            guard let host = Self.resolveHostView(from: probe) else { return }
            if hostView === host, panRecognizer != nil { return }

            detachPan()

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.name = Self.recognizerName
            pan.delegate = self
            pan.cancelsTouchesInView = false
            pan.maximumNumberOfTouches = 1
            host.addGestureRecognizer(pan)
            hostView = host
            panRecognizer = pan
        }

        private static func resolveHostView(from probe: UIView) -> UIView? {
            var responder: UIResponder? = probe
            while let current = responder {
                if let viewController = current as? UIViewController {
                    if let navigationController = viewController.navigationController {
                        return navigationController.view
                    }
                    return viewController.view
                }
                responder = current.next
            }

            var ancestor: UIView? = probe.superview
            while let view = ancestor {
                if view.bounds.width > 120, view.bounds.height > 120 {
                    return view
                }
                ancestor = view.superview
            }
            return probe.window
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let width = max(containerWidth, recognizer.view?.bounds.width ?? 0)
            guard width > 0 else { return }

            switch recognizer.state {
            case .began:
                dragIsHorizontal = nil
                dragAnchorProgress = nil

            case .changed:
                guard !popBridge.shouldDeferShellDismissGesture else { return }
                guard !navigator.stack.isEmpty else { return }

                let translation = recognizer.translation(in: recognizer.view)
                if dragIsHorizontal == nil {
                    let horizontal = abs(translation.x)
                    let vertical = abs(translation.y)
                    guard horizontal > 4 || vertical > 4 else { return }
                    dragIsHorizontal = horizontal >= vertical * 0.85
                }

                guard dragIsHorizontal == true else { return }
                guard translation.x >= 0 else { return }

                if dragAnchorProgress == nil {
                    dragAnchorProgress = navigator.slideProgress
                    navigator.beginInteractiveDragIfNeeded()
                }

                navigator.updateInteractiveDrag(
                    translationX: translation.x,
                    containerWidth: width,
                    anchorProgress: dragAnchorProgress ?? navigator.slideProgress
                )

            case .ended, .cancelled, .failed:
                defer {
                    dragAnchorProgress = nil
                    dragIsHorizontal = nil
                }
                guard dragIsHorizontal == true else { return }
                guard !popBridge.shouldDeferShellDismissGesture else {
                    if navigator.isInteractiveDragging {
                        navigator.finishInteractiveDrag(translationX: 0, containerWidth: width)
                    }
                    return
                }
                guard !navigator.stack.isEmpty else { return }

                let translation = recognizer.translation(in: recognizer.view)
                navigator.finishInteractiveDrag(
                    translationX: translation.x,
                    containerWidth: width
                )

            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            guard !popBridge.shouldDeferShellDismissGesture else { return false }
            guard !navigator.stack.isEmpty else { return false }

            var view: UIView? = touch.view
            while let current = view {
                if current is UIControl { return false }
                if current is UITextField || current is UITextView { return false }
                if current is UISlider || current is UISwitch { return false }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
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
