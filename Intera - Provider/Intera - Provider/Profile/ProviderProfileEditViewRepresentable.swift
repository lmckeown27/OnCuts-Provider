import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Hosts native `ProfileEditViewController` for the Account / profile experience (web parity).
struct ProviderProfileEditViewRepresentable: UIViewControllerRepresentable {
    @Environment(ProviderSession.self) private var session
    @Environment(ProviderShellNavigator.self) private var shellNavigator
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, shellNavigator: shellNavigator, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let profile = ProfileEditViewController()
        profile.delegate = context.coordinator
        profile.onRefresh = { try? await session.refreshProfileAfterSignIn() }
        profile.loadViewIfNeeded()
        profile.apply(initialState: ProfileEditInitialState(session: session))
        context.coordinator.lastAppliedSeed = Coordinator.seed(for: session)
        #if os(iOS)
        return ProviderOpaqueScreenContainerViewController(
            content: profile,
            fillColor: ProviderAppearance.shellBase
        )
        #else
        return profile
        #endif
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        let profile: ProfileEditViewController?
        #if os(iOS)
        if let container = uiViewController as? ProviderOpaqueScreenContainerViewController {
            profile = container.children.first { $0 is ProfileEditViewController } as? ProfileEditViewController
        } else {
            profile = uiViewController as? ProfileEditViewController
        }
        #else
        profile = uiViewController as? ProfileEditViewController
        #endif
        guard let profile else { return }
        profile.onRefresh = { try? await session.refreshProfileAfterSignIn() }
        let next = Coordinator.seed(for: session)
        guard next != context.coordinator.lastAppliedSeed else { return }
        context.coordinator.lastAppliedSeed = next
        profile.apply(initialState: ProfileEditInitialState(session: session))
    }

    @MainActor
    final class Coordinator: NSObject, ProfileEditViewControllerDelegate {
        let session: ProviderSession
        let shellNavigator: ProviderShellNavigator
        let dismiss: DismissAction
        var lastAppliedSeed: String = ""

        init(session: ProviderSession, shellNavigator: ProviderShellNavigator, dismiss: DismissAction) {
            self.session = session
            self.shellNavigator = shellNavigator
            self.dismiss = dismiss
        }

        static func seed(for session: ProviderSession) -> String {
            let b = session.barberProfile
            let spec = (b?.specialties ?? []).sorted().joined(separator: ",")
            let needsPw = session.authUser?.needsPlatformPassword.map { String($0) } ?? ""
            let avatar = b?.profilePictureUrl ?? ""
            return "\(session.authUser?.id ?? "")|\(needsPw)|\(b?.id ?? "")|\(avatar)|\(b?.bio ?? "")|\(b?.name ?? "")|\(b?.displayName ?? "")|\(b?.firstName ?? "")|\(b?.lastName ?? "")|\(b?.instagramHandle ?? "")|\(spec)|\(b?.isActive.map { String($0) } ?? "")"
        }

        func profileEditViewControllerDidCancel(_ controller: ProfileEditViewController) {
            if let nav = controller.navigationController, nav.viewControllers.count > 1 {
                nav.popViewController(animated: true)
            } else if !shellNavigator.isHub {
                shellNavigator.pop()
            } else {
                dismiss()
            }
        }

        func profileEditViewController(
            _ controller: ProfileEditViewController,
            didSave draft: ProfileEditDraft,
            completion: @escaping (Result<Void, Error>) -> Void
        ) {
            guard let barberId = session.barberProfile?.id else {
                completion(.failure(CoordinatorProfileError.noLinkedProvider))
                return
            }
            Task {
                do {
                    try await ProviderAuthService.updateMyBarberProfile(
                        barberId: barberId,
                        displayName: draft.displayName,
                        bio: draft.bio,
                        instagramHandle: draft.instagramUsername,
                        specialties: Array(draft.selectedSpecialties).sorted(),
                        isActive: !draft.hideFromConsumers
                    )
                    try await session.refreshProfileAfterSignIn()
                    await MainActor.run {
                        completion(.success(()))
                        if let nav = controller.navigationController, nav.viewControllers.count > 1 {
                            nav.popViewController(animated: true)
                        } else if !shellNavigator.isHub {
                            shellNavigator.pop()
                        } else {
                            dismiss()
                        }
                    }
                } catch {
                    await MainActor.run { completion(.failure(error)) }
                }
            }
        }

        func profileEditViewController(
            _ controller: ProfileEditViewController,
            didRequestDeleteAccount password: String?,
            completion: @escaping (Result<Void, Error>) -> Void
        ) {
            Task {
                do {
                    try await session.deleteAccount(password: password)
                    await MainActor.run { completion(.success(())) }
                } catch {
                    await MainActor.run { completion(.failure(error)) }
                }
            }
        }
    }
}

private enum CoordinatorProfileError: LocalizedError {
    case noLinkedProvider
    var errorDescription: String? {
        switch self {
        case .noLinkedProvider:
            return "No barber profile is linked to this account yet. Finish barber setup on CampusCuts, then refresh."
        }
    }
}
