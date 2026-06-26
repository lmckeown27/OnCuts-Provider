import SwiftUI
import UIKit

// MARK: - Orthogonal scroll handoff

/// Lets users start vertical or horizontal scheduler pans without waiting for the other axis to fully settle.
struct ProviderScheduleGridOrthogonalScrollHandoff: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.scheduleConfigure(anchor: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var verticalScrollView: UIScrollView?
        private weak var horizontalScrollView: UIScrollView?
        private var wiredScrollViews: [UIScrollView] = []
        private var touchRecognizers: [UILongPressGestureRecognizer] = []
        private var configureTask: DispatchWorkItem?

        func scheduleConfigure(anchor: UIView) {
            configureTask?.cancel()
            let task = DispatchWorkItem { [weak self, weak anchor] in
                guard let self, let anchor else { return }
                self.configureIfNeeded(anchor: anchor)
            }
            configureTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: task)
        }

        func teardown() {
            configureTask?.cancel()
            configureTask = nil
            for scrollView in wiredScrollViews {
                scrollView.panGestureRecognizer.removeTarget(self, action: #selector(scrollPanChanged(_:)))
            }
            wiredScrollViews = []
            for recognizer in touchRecognizers {
                recognizer.view?.removeGestureRecognizer(recognizer)
            }
            touchRecognizers = []
            verticalScrollView = nil
            horizontalScrollView = nil
        }

        private func configureIfNeeded(anchor: UIView) {
            let scrollViews = anchor.enclosingProviderScheduleScrollViews
            guard !scrollViews.isEmpty else { return }

            let horizontal = scrollViews.first(where: Self.canScrollHorizontally)
            let vertical = scrollViews.first(where: Self.canScrollVertically)

            let needsRewire = wiredScrollViews.isEmpty
                || verticalScrollView !== vertical
                || horizontalScrollView !== horizontal

            guard needsRewire else { return }

            teardown()

            verticalScrollView = vertical
            horizontalScrollView = horizontal

            let targets = [vertical, horizontal].compactMap { $0 }
            for scrollView in targets {
                scrollView.isDirectionalLockEnabled = false
                scrollView.delaysContentTouches = false
                scrollView.panGestureRecognizer.addTarget(self, action: #selector(scrollPanChanged(_:)))

                let touch = UILongPressGestureRecognizer(
                    target: self,
                    action: #selector(immediateTouch(_:))
                )
                touch.minimumPressDuration = 0
                touch.cancelsTouchesInView = false
                touch.delaysTouchesBegan = false
                touch.delaysTouchesEnded = false
                touch.delegate = self
                scrollView.addGestureRecognizer(touch)
                touchRecognizers.append(touch)

                wiredScrollViews.append(scrollView)
            }
        }

        private static func canScrollHorizontally(_ scrollView: UIScrollView) -> Bool {
            scrollView.contentSize.width > scrollView.bounds.width + 1
        }

        private static func canScrollVertically(_ scrollView: UIScrollView) -> Bool {
            scrollView.contentSize.height > scrollView.bounds.height + 1
        }

        @objc private func immediateTouch(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began else { return }
            stopAllDeceleration()
        }

        @objc private func scrollPanChanged(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .began else { return }
            stopSiblingMomentum(for: recognizer.view as? UIScrollView)
        }

        private func stopAllDeceleration() {
            for scrollView in wiredScrollViews where scrollView.isDecelerating {
                scrollView.setContentOffset(scrollView.contentOffset, animated: false)
            }
        }

        private func stopSiblingMomentum(for scrollView: UIScrollView?) {
            guard let scrollView else { return }
            let sibling = scrollView === verticalScrollView ? horizontalScrollView : verticalScrollView
            if let sibling, sibling.isDecelerating {
                sibling.setContentOffset(sibling.contentOffset, animated: false)
            }
            if scrollView.isDecelerating {
                scrollView.setContentOffset(scrollView.contentOffset, animated: false)
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard touchRecognizers.contains(where: { $0 === gestureRecognizer })
                || touchRecognizers.contains(where: { $0 === otherGestureRecognizer }) else {
                return false
            }

            if otherGestureRecognizer === verticalScrollView?.panGestureRecognizer
                || otherGestureRecognizer === horizontalScrollView?.panGestureRecognizer {
                return true
            }
            if gestureRecognizer === verticalScrollView?.panGestureRecognizer
                || gestureRecognizer === horizontalScrollView?.panGestureRecognizer {
                return true
            }
            return false
        }
    }
}

extension UIView {
    var enclosingProviderScheduleScrollViews: [UIScrollView] {
        sequence(first: self, next: { $0.superview })
            .compactMap { $0 as? UIScrollView }
            .reduce(into: [UIScrollView]()) { result, scrollView in
                if !result.contains(where: { $0 === scrollView }) {
                    result.append(scrollView)
                }
            }
    }
}
