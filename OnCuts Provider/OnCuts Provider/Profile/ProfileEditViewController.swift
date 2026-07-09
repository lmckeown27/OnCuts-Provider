import PhotosUI
import UIKit

// MARK: - Delegate

@MainActor
protocol ProfileEditViewControllerDelegate: AnyObject {
    func profileEditViewControllerDidCancel(_ controller: ProfileEditViewController)
    func profileEditViewController(
        _ controller: ProfileEditViewController,
        didSave draft: ProfileEditDraft,
        completion: @escaping (Result<Void, Error>) -> Void
    )
    func profileEditViewController(
        _ controller: ProfileEditViewController,
        didRequestDeleteAccount password: String?,
        completion: @escaping (Result<Void, Error>) -> Void
    )
}

// MARK: - Layout constants

private enum Layout {
    static let margin: CGFloat = 16
    static let stackSpacing: CGFloat = 24
    static let cardCornerRadius: CGFloat = 12
    static let photoSide: CGFloat = 200
    static let photoCornerRadius: CGFloat = 16
    static let editableFieldCornerRadius: CGFloat = 10
    static let editableFieldBorderWidth: CGFloat = 1
}

/// Shared look for fields users can type in on the dark Account screen.
private enum EditableFieldChrome {
    /// Light grey wells only on inputs — page/cards stay on the lava shell.
    static let fieldFill = UIColor(red: 0.90, green: 0.91, blue: 0.93, alpha: 1)
    static let fieldText = UIColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1)
    static let fieldPlaceholder = UIColor(red: 0.42, green: 0.44, blue: 0.48, alpha: 1)
    static let fieldBorder = UIColor.black.withAlphaComponent(0.10)
    static let fieldTint = UIColor(red: 90 / 255, green: 114 / 255, blue: 104 / 255, alpha: 1)
    /// Unselected specialty chips (not the light text wells).
    static let tagFill = UIColor.white.withAlphaComponent(0.10)
    static let oliveAccent = UIColor(red: 90 / 255, green: 114 / 255, blue: 104 / 255, alpha: 0.45)
}

private func editableFieldPlaceholder(_ text: String) -> NSAttributedString {
    NSAttributedString(
        string: text,
        attributes: [
            .foregroundColor: EditableFieldChrome.fieldPlaceholder,
            .font: UIFont.providerPreferred(forTextStyle: .body),
        ]
    )
}

// MARK: - ProfileEditViewController

final class ProfileEditViewController: UIViewController, UITextFieldDelegate, UITextViewDelegate,
    UIGestureRecognizerDelegate {

    weak var delegate: ProfileEditViewControllerDelegate?

    /// Pull-to-refresh: assigned by `ProviderProfileEditViewRepresentable` (reloads session / profile).
    var onRefresh: (() async -> Void)?

    private var userId: String = ""
    private var canDeleteWithoutPassword = false
    private var barberId: String?
    private var selectedSpecialties = Set<String>()

    private let deletePasswordField: UITextField = {
        let t = UITextField()
        t.translatesAutoresizingMaskIntoConstraints = false
        t.attributedPlaceholder = editableFieldPlaceholder("Your password")
        t.borderStyle = .none
        t.backgroundColor = .clear
        t.isSecureTextEntry = true
        t.textColor = EditableFieldChrome.fieldText
        t.tintColor = EditableFieldChrome.fieldTint
        t.autocapitalizationType = .none
        t.autocorrectionType = .no
        return t
    }()

    private let deleteConfirmField: UITextField = {
        let t = UITextField()
        t.translatesAutoresizingMaskIntoConstraints = false
        t.attributedPlaceholder = editableFieldPlaceholder("DELETE")
        t.borderStyle = .none
        t.backgroundColor = .clear
        t.textColor = EditableFieldChrome.fieldText
        t.tintColor = EditableFieldChrome.fieldTint
        t.autocapitalizationType = .allCharacters
        t.autocorrectionType = .no
        return t
    }()

    private let deletePasswordErrorLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .providerPreferred(forTextStyle: .caption1)
        l.textColor = .systemRed
        l.numberOfLines = 0
        l.isHidden = true
        return l
    }()

    private let deleteAccountButton: UIButton = {
        var c = UIButton.Configuration.filled()
        c.title = "Delete My Account"
        c.baseBackgroundColor = .systemRed
        c.baseForegroundColor = .white
        c.cornerStyle = .medium
        let b = UIButton(configuration: c)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private var deletePasswordWrapper: UIView?
    private weak var deleteAccountCardView: UIView?
    private var keyboardBottomInset: CGFloat = 0
    private var isDeletingAccount = false
    private var profilePhotoUploadTask: Task<Void, Never>?
    private var isUploadingProfilePhoto = false {
        didSet { updateUploadPhotoButtonChrome() }
    }

    // MARK: - UI Initialization

    private let scrollView: UIScrollView = {
        let s = UIScrollView()
        s.translatesAutoresizingMaskIntoConstraints = false
        s.alwaysBounceVertical = true
        s.keyboardDismissMode = .interactive
        return s
    }()

    private let contentStack: UIStackView = {
        let s = UIStackView()
        s.translatesAutoresizingMaskIntoConstraints = false
        s.axis = .vertical
        s.spacing = Layout.stackSpacing
        s.isLayoutMarginsRelativeArrangement = true
        s.layoutMargins = UIEdgeInsets(top: Layout.margin, left: Layout.margin, bottom: Layout.margin, right: Layout.margin)
        return s
    }()

    private let profileImageView: UIImageView = {
        let v = UIImageView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.contentMode = .scaleAspectFill
        v.clipsToBounds = true
        v.layer.cornerRadius = Layout.photoCornerRadius
        v.backgroundColor = .tertiarySystemFill
        v.layer.borderWidth = Layout.editableFieldBorderWidth
        v.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        return v
    }()

    private let uploadPhotoButton: UIButton = {
        var c = UIButton.Configuration.filled()
        c.title = "Upload Photo"
        c.cornerStyle = .medium
        // Brand olive (`Color.providerOlive`) with light label for strong contrast vs. the old tinted style.
        c.baseBackgroundColor = UIColor(red: 90 / 255, green: 114 / 255, blue: 104 / 255, alpha: 1)
        c.baseForegroundColor = .white
        c.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18)
        c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var o = incoming
            let base = o.font ?? UIFont.providerPreferred(forTextStyle: .subheadline)
            o.font = UIFont.provider(size: base.pointSize, weight: .semibold)
            return o
        }
        let b = UIButton(configuration: c)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private let displayNameField: UITextField = {
        let t = UITextField()
        t.translatesAutoresizingMaskIntoConstraints = false
        t.attributedPlaceholder = editableFieldPlaceholder("Your name")
        t.borderStyle = .none
        t.backgroundColor = .clear
        t.font = .providerPreferred(forTextStyle: .body)
        t.textColor = EditableFieldChrome.fieldText
        t.tintColor = EditableFieldChrome.fieldTint
        t.clearButtonMode = .never
        return t
    }()

    private let bioTextView: UITextView = {
        let v = UITextView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.font = .providerPreferred(forTextStyle: .body)
        v.backgroundColor = .clear
        v.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        v.textColor = EditableFieldChrome.fieldText
        v.tintColor = EditableFieldChrome.fieldTint
        v.isEditable = true
        v.isSelectable = true
        return v
    }()

    private let bioCountLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .providerPreferred(forTextStyle: .caption2)
        l.textColor = .secondaryLabel
        l.textAlignment = .right
        return l
    }()

    private let instagramPrefixLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.text = "@"
        l.font = .providerPreferred(forTextStyle: .body)
        l.textColor = .secondaryLabel
        return l
    }()

    private let instagramField: UITextField = {
        let t = UITextField()
        t.translatesAutoresizingMaskIntoConstraints = false
        t.attributedPlaceholder = editableFieldPlaceholder("username")
        t.borderStyle = .none
        t.backgroundColor = .clear
        t.font = .providerPreferred(forTextStyle: .body)
        t.textColor = EditableFieldChrome.fieldText
        t.tintColor = EditableFieldChrome.fieldTint
        t.autocapitalizationType = .none
        t.autocorrectionType = .no
        t.clearButtonMode = .never
        return t
    }()

    private let hideProfileSwitch: UISwitch = {
        let s = UISwitch()
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let specialtiesContainer: UIStackView = {
        let s = UIStackView()
        s.translatesAutoresizingMaskIntoConstraints = false
        s.axis = .vertical
        s.spacing = 8
        s.alignment = .fill
        return s
    }()

    private var specialtyButtons: [String: UIButton] = [:]

    private let cancelButton: UIButton = {
        var c = UIButton.Configuration.bordered()
        c.title = "Cancel"
        let b = UIButton(configuration: c)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private let saveButton: UIButton = {
        var c = UIButton.Configuration.filled()
        c.title = "Save"
        c.baseBackgroundColor = UIColor(red: 0.35, green: 0.45, blue: 0.22, alpha: 1)
        c.baseForegroundColor = .white
        let b = UIButton(configuration: c)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private let footerStack: UIStackView = {
        let s = UIStackView()
        s.translatesAutoresizingMaskIntoConstraints = false
        s.axis = .horizontal
        s.spacing = 12
        s.distribution = .fillEqually
        return s
    }()

    private var imageDownloadTask: URLSessionDataTask?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        scrollView.backgroundColor = .clear
        displayNameField.delegate = self
        instagramField.delegate = self
        deletePasswordField.delegate = self
        deleteConfirmField.delegate = self
        bioTextView.delegate = self
        uploadPhotoButton.addTarget(self, action: #selector(uploadPhotoTapped), for: .touchUpInside)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        assembleHierarchy()
        assembleConstraints()
        configureVisibilitySwitchChrome()
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(handleRefreshControl), for: .valueChanged)
        scrollView.refreshControl = refreshControl

        let dismissKeyboardTap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboardFromBackgroundTap))
        dismissKeyboardTap.cancelsTouchesInView = false
        dismissKeyboardTap.delegate = self
        view.addGestureRecognizer(dismissKeyboardTap)
        updateUploadPhotoButtonChrome()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        imageDownloadTask?.cancel()
        profilePhotoUploadTask?.cancel()
    }

    // MARK: - Public configuration

    func apply(initialState: ProfileEditInitialState) {
        userId = initialState.userId
        canDeleteWithoutPassword = initialState.canDeleteWithoutPassword
        barberId = initialState.barberId
        selectedSpecialties = initialState.selectedSpecialties
        displayNameField.text = initialState.displayName
        bioTextView.text = initialState.bio
        instagramField.text = initialState.instagramUsername
        applyEditableFieldTextColors()
        hideProfileSwitch.isOn = initialState.hideFromConsumers
        refreshBioCount()
        rebuildSpecialtyTags()
        loadRemoteProfileImage(from: initialState.avatarURL)
    }

    func currentDraft() -> ProfileEditDraft {
        ProfileEditDraft(
            displayName: displayNameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            bio: bioTextView.text ?? "",
            instagramUsername: instagramField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            hideFromConsumers: hideProfileSwitch.isOn,
            selectedSpecialties: selectedSpecialties
        )
    }

    // MARK: - Hierarchy

    private func assembleHierarchy() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        contentStack.addArrangedSubview(photoCard())
        contentStack.addArrangedSubview(displayNameCard())
        contentStack.addArrangedSubview(bioCard())
        contentStack.addArrangedSubview(specialtiesCard())
        contentStack.addArrangedSubview(instagramCard())
        contentStack.addArrangedSubview(visibilityCard())
        contentStack.addArrangedSubview(deleteAccountCard())

        deleteAccountButton.addTarget(self, action: #selector(deleteAccountTapped), for: .touchUpInside)

        footerStack.addArrangedSubview(cancelButton)
        footerStack.addArrangedSubview(saveButton)
        contentStack.addArrangedSubview(footerStack)
    }

    // MARK: - Constraints Assembly

    private func assembleConstraints() {
        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: g.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: g.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: g.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: g.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    private func configureVisibilitySwitchChrome() {
        let olive = UIColor(red: 90 / 255, green: 114 / 255, blue: 104 / 255, alpha: 1)
        hideProfileSwitch.onTintColor = olive
        hideProfileSwitch.tintColor = .secondaryLabel
    }

    /// Border/fill on a wrapper — not on `UITextField` itself. Background on the field paints above the text
    /// and reads as an opaque overlay (Display Name / Instagram).
    private func wrapEditableTextField(_ field: UITextField) -> UIView {
        let shell = UIView()
        shell.translatesAutoresizingMaskIntoConstraints = false
        shell.backgroundColor = EditableFieldChrome.fieldFill
        shell.layer.cornerRadius = Layout.editableFieldCornerRadius
        shell.layer.borderWidth = Layout.editableFieldBorderWidth
        shell.layer.borderColor = EditableFieldChrome.fieldBorder.cgColor

        let pencil = UIImageView()
        pencil.translatesAutoresizingMaskIntoConstraints = false
        pencil.isUserInteractionEnabled = false
        let cfg = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        pencil.image = UIImage(systemName: "square.and.pencil", withConfiguration: cfg)
        pencil.tintColor = EditableFieldChrome.fieldTint
        pencil.setContentHuggingPriority(.required, for: .horizontal)
        pencil.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [field, pencil])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 4
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 10)

        shell.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: shell.topAnchor),
            row.leadingAnchor.constraint(equalTo: shell.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: shell.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: shell.bottomAnchor),
            shell.heightAnchor.constraint(equalToConstant: 48),
            pencil.widthAnchor.constraint(equalToConstant: 24),
            pencil.heightAnchor.constraint(equalToConstant: 24),
        ])
        return shell
    }

    private func applyEditableFieldChrome(to container: UIView) {
        container.backgroundColor = EditableFieldChrome.fieldFill
        container.layer.cornerRadius = Layout.editableFieldCornerRadius
        container.layer.borderWidth = Layout.editableFieldBorderWidth
        container.layer.borderColor = EditableFieldChrome.fieldBorder.cgColor
    }

    private func applyEditableFieldTextColors() {
        displayNameField.textColor = EditableFieldChrome.fieldText
        displayNameField.tintColor = EditableFieldChrome.fieldTint
        instagramField.textColor = EditableFieldChrome.fieldText
        instagramField.tintColor = EditableFieldChrome.fieldTint
        bioTextView.textColor = EditableFieldChrome.fieldText
        bioTextView.tintColor = EditableFieldChrome.fieldTint
    }

    // MARK: - Cards

    private func photoCard() -> UIView {
        let photoWrap = UIView()
        photoWrap.translatesAutoresizingMaskIntoConstraints = false
        photoWrap.addSubview(profileImageView)
        NSLayoutConstraint.activate([
            profileImageView.topAnchor.constraint(equalTo: photoWrap.topAnchor),
            profileImageView.bottomAnchor.constraint(equalTo: photoWrap.bottomAnchor),
            profileImageView.centerXAnchor.constraint(equalTo: photoWrap.centerXAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: Layout.photoSide),
            profileImageView.heightAnchor.constraint(equalToConstant: Layout.photoSide),
        ])

        let uploadRow = UIStackView(arrangedSubviews: [uploadPhotoButton])
        uploadRow.axis = .horizontal
        uploadRow.alignment = .center
        uploadRow.translatesAutoresizingMaskIntoConstraints = false

        let inner = UIStackView(arrangedSubviews: [photoWrap, uploadRow])
        inner.axis = .vertical
        inner.spacing = 16
        inner.alignment = .fill
        inner.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            uploadRow.leadingAnchor.constraint(equalTo: inner.leadingAnchor),
        ])

        return wrapCard(
            title: "Profile Photo",
            subtitle: "Tap Upload Photo to choose a new picture. Your photo uploads and saves to your barber card immediately.",
            content: inner
        )
    }

    private func displayNameCard() -> UIView {
        let inner = UIStackView(arrangedSubviews: [wrapEditableTextField(displayNameField)])
        inner.axis = .vertical
        inner.translatesAutoresizingMaskIntoConstraints = false
        return wrapCard(
            title: "Display Name",
            subtitle: "Tap the field below to edit. This is the name shown on your barber card.",
            content: inner
        )
    }

    private func bioCard() -> UIView {
        let bioWrap = UIView()
        bioWrap.translatesAutoresizingMaskIntoConstraints = false
        applyEditableFieldChrome(to: bioWrap)
        bioWrap.addSubview(bioTextView)
        bioWrap.addSubview(bioCountLabel)
        NSLayoutConstraint.activate([
            bioTextView.topAnchor.constraint(equalTo: bioWrap.topAnchor),
            bioTextView.leadingAnchor.constraint(equalTo: bioWrap.leadingAnchor),
            bioTextView.trailingAnchor.constraint(equalTo: bioWrap.trailingAnchor),
            bioTextView.heightAnchor.constraint(equalToConstant: 140),
            bioCountLabel.topAnchor.constraint(equalTo: bioTextView.bottomAnchor, constant: 6),
            bioCountLabel.trailingAnchor.constraint(equalTo: bioWrap.trailingAnchor),
            bioCountLabel.bottomAnchor.constraint(equalTo: bioWrap.bottomAnchor),
        ])
        return wrapCard(
            title: "Bio",
            subtitle: "Tap the text area below to edit. Tell customers what sets you apart.",
            content: bioWrap
        )
    }

    private func specialtiesCard() -> UIView {
        return wrapCard(
            title: "Specialties",
            subtitle: "Tap a tag to add or remove specialties you want to highlight.",
            content: specialtiesContainer
        )
    }

    private func instagramCard() -> UIView {
        let row = UIStackView(arrangedSubviews: [instagramPrefixLabel, wrapEditableTextField(instagramField)])
        row.axis = .horizontal
        row.spacing = 6
        row.alignment = .center
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        instagramPrefixLabel.setContentHuggingPriority(.required, for: .horizontal)
        instagramPrefixLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        return wrapCard(
            title: "Instagram (Portfolio)",
            subtitle: "Tap the field below to edit your handle (without @). Shown on your barber card for more examples.",
            content: row
        )
    }

    private func deleteAccountCard() -> UIView {
        let warning = UILabel()
        warning.text =
            "This action is permanent and cannot be undone. All your data, bookings, and account information will be permanently deleted."
        warning.font = .providerPreferred(forTextStyle: .subheadline)
        warning.textColor = .systemRed
        warning.numberOfLines = 0

        var rows: [UIView] = [warning]

        if canDeleteWithoutPassword {
            let deviceNote = UILabel()
            deviceNote.text = "Confirm with Face ID, Touch ID, or your device passcode."
            deviceNote.font = .providerPreferred(forTextStyle: .caption1)
            deviceNote.textColor = .secondaryLabel
            deviceNote.numberOfLines = 0
            rows.append(deviceNote)
        } else {
            let passLabel = UILabel()
            passLabel.text = "Enter your password to confirm"
            passLabel.font = .providerPreferred(forTextStyle: .subheadline)
            passLabel.textColor = .label
            rows.append(passLabel)

            let wrapper = wrapEditableTextField(deletePasswordField)
            deletePasswordWrapper = wrapper
            rows.append(wrapper)
            rows.append(deletePasswordErrorLabel)
        }

        let confirmLabel = UILabel()
        confirmLabel.text = "Type DELETE to confirm"
        confirmLabel.font = .providerPreferred(forTextStyle: .subheadline)
        confirmLabel.textColor = .label
        rows.append(confirmLabel)
        rows.append(wrapEditableTextField(deleteConfirmField))
        rows.append(deleteAccountButton)

        let stack = UIStackView(arrangedSubviews: rows)
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let card = wrapCard(
            title: "Delete Account",
            subtitle: nil,
            content: stack
        )
        deleteAccountCardView = card
        return card
    }

    private func visibilityCard() -> UIView {
        let title = UILabel()
        title.text = "Hide my profile from consumers"
        title.font = .providerPreferred(forTextStyle: .body)
        title.textColor = .label
        title.numberOfLines = 0

        let sub = UILabel()
        sub.text = "Your barber card will not appear in search results"
        sub.font = .providerPreferred(forTextStyle: .caption1)
        sub.textColor = .secondaryLabel
        sub.numberOfLines = 0

        let labels = UIStackView(arrangedSubviews: [title, sub])
        labels.axis = .vertical
        labels.spacing = 4
        labels.translatesAutoresizingMaskIntoConstraints = false

        let row = UIStackView(arrangedSubviews: [labels, hideProfileSwitch])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        hideProfileSwitch.setContentHuggingPriority(.required, for: .horizontal)

        return wrapCard(
            title: "Visibility",
            subtitle: "Use the switch to change whether consumers can find your barber card in search.",
            content: row
        )
    }

    private func wrapCard(title: String, subtitle: String?, content: UIView) -> UIView {
        let wrap = UIView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        wrap.layer.cornerRadius = Layout.cardCornerRadius
        wrap.layer.masksToBounds = true

        let v = UIStackView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.axis = .vertical
        v.spacing = 12
        v.isLayoutMarginsRelativeArrangement = true
        v.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let t = UILabel()
        t.text = title
        t.font = .provider(size: 18, weight: .bold)
        t.textColor = .label
        v.addArrangedSubview(t)

        if let subtitle, !subtitle.isEmpty {
            let s = UILabel()
            s.text = subtitle
            s.font = .providerPreferred(forTextStyle: .subheadline)
            s.textColor = .secondaryLabel
            s.numberOfLines = 0
            v.addArrangedSubview(s)
        }

        v.addArrangedSubview(content)
        wrap.addSubview(v)

        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: wrap.topAnchor),
            v.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            v.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
        ])
        return wrap
    }

    // MARK: - Specialties (wrapping rows)

    private func rebuildSpecialtyTags() {
        specialtiesContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }
        specialtyButtons.removeAll()

        let maxWidth = max(120, view.bounds.width > 0 ? view.bounds.width - (Layout.margin * 2 + 32) : UIScreen.main.bounds.width - (Layout.margin * 2 + 32))

        var row = makeTagRow()
        var rowWidth: CGFloat = 0

        func pushRowIfNeeded(forIncomingWidth w: CGFloat) {
            if !row.arrangedSubviews.isEmpty, rowWidth + 8 + w > maxWidth {
                specialtiesContainer.addArrangedSubview(row)
                row = makeTagRow()
                rowWidth = 0
            }
        }

        for token in ProfileEditDefaults.allSpecialtiesOrdered {
            let button = makeSpecialtyButton(token)
            specialtyButtons[token] = button
            let w = tagChipWidth(for: token)
            pushRowIfNeeded(forIncomingWidth: w)
            row.addArrangedSubview(button)
            if row.arrangedSubviews.count > 1 { rowWidth += 8 }
            rowWidth += w
        }
        if !row.arrangedSubviews.isEmpty {
            specialtiesContainer.addArrangedSubview(row)
        }
        applySpecialtyStyles()
    }

    private func makeTagRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        row.distribution = .fillProportionally
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func tagChipWidth(for title: String) -> CGFloat {
        let font = UIFont.providerPreferred(forTextStyle: .subheadline)
        let attrs = [NSAttributedString.Key.font: font]
        let size = (title as NSString).size(withAttributes: attrs)
        return ceil(size.width) + 28
    }

    private func makeSpecialtyButton(_ title: String) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .providerPreferred(forTextStyle: .subheadline)
        b.titleLabel?.lineBreakMode = .byTruncatingTail
        b.layer.cornerRadius = 16
        b.layer.masksToBounds = true
        b.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        b.addTarget(self, action: #selector(specialtyTapped(_:)), for: .touchUpInside)
        return b
    }

    @objc private func specialtyTapped(_ sender: UIButton) {
        guard let title = sender.title(for: .normal) else { return }
        if selectedSpecialties.contains(title) {
            selectedSpecialties.remove(title)
        } else {
            selectedSpecialties.insert(title)
        }
        applySpecialtyStyles()
    }

    private func applySpecialtyStyles() {
        for (title, button) in specialtyButtons {
            let on = selectedSpecialties.contains(title)
            if on {
                button.backgroundColor = UIColor(red: 0.35, green: 0.45, blue: 0.22, alpha: 1)
                button.setTitleColor(.white, for: .normal)
                button.layer.borderWidth = 0
                button.layer.borderColor = nil
            } else {
                button.backgroundColor = EditableFieldChrome.tagFill
                button.setTitleColor(.label, for: .normal)
                button.layer.borderWidth = Layout.editableFieldBorderWidth
                button.layer.borderColor = EditableFieldChrome.oliveAccent.cgColor
            }
        }
    }

    // MARK: - Network Image Pull

    private func updateUploadPhotoButtonChrome() {
        let busy = isUploadingProfilePhoto || isDeletingAccount
        uploadPhotoButton.isEnabled = !busy
        saveButton.isEnabled = !busy
        if #available(iOS 15.0, *) {
            uploadPhotoButton.configuration?.showsActivityIndicator = isUploadingProfilePhoto
            uploadPhotoButton.configuration?.title = isUploadingProfilePhoto ? "Uploading…" : "Upload Photo"
        }
    }

    private func handlePickedProfileImage(_ image: UIImage) {
        profileImageView.image = image
        profilePhotoUploadTask?.cancel()
        profilePhotoUploadTask = Task { @MainActor [weak self] in
            await self?.uploadPickedProfilePhoto(image)
        }
    }

    @MainActor
    private func uploadPickedProfilePhoto(_ image: UIImage) async {
        guard !Task.isCancelled else { return }
        guard !userId.isEmpty else {
            presentSimpleAlert(
                title: "Couldn't upload",
                message: "Sign in again, then try uploading your photo."
            )
            return
        }
        guard let jpeg = ProviderAuthService.jpegDataForProfileUpload(from: image) else {
            presentSimpleAlert(title: "Couldn't upload", message: "This image could not be prepared for upload.")
            return
        }

        isUploadingProfilePhoto = true
        defer { isUploadingProfilePhoto = false }

        do {
            let urlString = try await ProviderAuthService.uploadProfilePhoto(jpegData: jpeg)
            guard !Task.isCancelled else { return }
            if let url = URL(string: urlString) {
                loadRemoteProfileImage(from: url)
            }
            await onRefresh?()
        } catch let err as OnCutsHTTPError {
            let message = err.errorDescription ?? "Upload failed."
            presentSimpleAlert(title: "Couldn't upload photo", message: message)
        } catch {
            presentSimpleAlert(title: "Couldn't upload photo", message: error.localizedDescription)
        }
    }

    private func loadRemoteProfileImage(from url: URL) {
        imageDownloadTask?.cancel()
        imageDownloadTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let img = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.profileImageView.image = img
            }
        }
        imageDownloadTask?.resume()
    }

    // MARK: - UI Control Target Actions

    @objc private func handleRefreshControl() {
        Task { @MainActor in
            await onRefresh?()
            scrollView.refreshControl?.endRefreshing()
        }
    }

    @objc private func dismissKeyboardFromBackgroundTap() {
        view.endEditing(true)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    @objc private func uploadPhotoTapped() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Photo Library", style: .default) { [weak self] _ in
            self?.presentPhotoLibraryPicker()
        })
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            sheet.addAction(UIAlertAction(title: "Take Photo", style: .default) { [weak self] _ in
                self?.presentCameraPicker()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = uploadPhotoButton
            pop.sourceRect = uploadPhotoButton.bounds
        }
        present(sheet, animated: true)
    }

    private func presentPhotoLibraryPicker() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func presentCameraPicker() {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func cancelTapped() {
        delegate?.profileEditViewControllerDidCancel(self)
    }

    @objc private func deleteAccountTapped() {
        view.endEditing(true)
        guard !userId.isEmpty else {
            presentSimpleAlert(title: "Account unavailable", message: "Sign in again, then try deleting your account.")
            return
        }

        deletePasswordErrorLabel.isHidden = true
        deletePasswordErrorLabel.text = nil

        let confirmText = deleteConfirmField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard confirmText == "DELETE" else {
            presentSimpleAlert(title: "Confirmation required", message: "Type DELETE in the confirmation field to continue.")
            return
        }

        let password = deletePasswordField.text ?? ""
        if !canDeleteWithoutPassword, password.isEmpty {
            deletePasswordErrorLabel.text = "Password is required"
            deletePasswordErrorLabel.isHidden = false
            return
        }

        let alert = UIAlertController(
            title: "Delete account?",
            message: "This permanently deletes your account and cannot be undone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.performAccountDeletion(password: password)
        })
        present(alert, animated: true)
    }

    private func performAccountDeletion(password: String) {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        deleteAccountButton.isEnabled = false

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isDeletingAccount = false
                self.deleteAccountButton.isEnabled = true
            }

            do {
                if self.canDeleteWithoutPassword {
                    try await ProviderDeviceAuthentication.requireDeviceOwnerAuthentication()
                }

                let passwordForAPI = self.canDeleteWithoutPassword ? nil : password
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    guard let delegate = self.delegate else {
                        continuation.resume(throwing: NSError(
                            domain: "ProfileEdit",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Account action is unavailable."]
                        ))
                        return
                    }
                    delegate.profileEditViewController(self, didRequestDeleteAccount: passwordForAPI) { result in
                        continuation.resume(with: result)
                    }
                }
            } catch let error as ProviderDeviceAuthentication.AuthError {
                if case .cancelled = error { return }
                self.presentSimpleAlert(title: "Couldn’t verify identity", message: error.localizedDescription)
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                if !self.canDeleteWithoutPassword,
                   message.localizedCaseInsensitiveContains("password") || message.localizedCaseInsensitiveContains("incorrect")
                {
                    self.deletePasswordErrorLabel.text = "Incorrect password"
                    self.deletePasswordErrorLabel.isHidden = false
                } else {
                    self.presentSimpleAlert(title: "Couldn’t delete account", message: message)
                }
            }
        }
    }

    private func presentSimpleAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @objc private func saveTapped() {
        let draft = currentDraft()
        saveButton.isEnabled = false
        delegate?.profileEditViewController(self, didSave: draft) { [weak self] result in
            DispatchQueue.main.async {
                self?.saveButton.isEnabled = true
                if case let .failure(err) = result {
                    let a = UIAlertController(title: "Couldn’t save", message: err.localizedDescription, preferredStyle: .alert)
                    a.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(a, animated: true)
                }
            }
        }
    }

    @objc private func keyboardWillChangeFrame(_ note: Notification) {
        applyKeyboardInsets(from: note)
        if let active = scrollView.firstResponderSubview {
            scrollInputIntoView(active, animated: true, keyboardNote: note)
        }
    }

    @objc private func keyboardWillHide(_ note: Notification) {
        keyboardBottomInset = 0
        scrollView.contentInset.bottom = 0
        scrollView.verticalScrollIndicatorInsets.bottom = 0
        scrollView.scrollIndicatorInsets.bottom = 0
    }

    private func applyKeyboardInsets(from note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let keyboardInView: CGRect
        if let window = view.window {
            keyboardInView = view.convert(frame, from: window)
        } else {
            keyboardInView = frame
        }
        keyboardBottomInset = max(0, view.bounds.maxY - keyboardInView.minY)
        applyStoredKeyboardInsets()
    }

    private func applyStoredKeyboardInsets() {
        let deleteFocused = scrollView.firstResponderSubview.map(isDeleteAccountInput) ?? false
        let extraPadding: CGFloat = deleteFocused ? 48 : 24
        let inset = keyboardBottomInset + extraPadding
        scrollView.contentInset.bottom = inset
        scrollView.verticalScrollIndicatorInsets.bottom = inset
        scrollView.scrollIndicatorInsets.bottom = inset
    }

    private func isDeleteAccountInput(_ view: UIView) -> Bool {
        view === deletePasswordField || view === deleteConfirmField
    }

    /// Rect in `contentStack` coordinates for the region that should stay above the keyboard.
    private func focusRectForInput(_ input: UIView) -> CGRect {
        if isDeleteAccountInput(input), let card = deleteAccountCardView {
            return card.convert(card.bounds, to: contentStack).insetBy(dx: 0, dy: -12)
        }
        return input.convert(input.bounds, to: contentStack).insetBy(dx: 0, dy: -16)
    }

    /// Scrolls so `input` sits above the keyboard. Uses explicit `contentOffset` math in content
    /// coordinates — `scrollRectToVisible` with rects converted to the scroll view was under-scrolling
    /// the delete-account fields at the bottom of this long form.
    private func scrollInputIntoView(_ input: UIView, animated: Bool, keyboardNote: Notification? = nil) {
        guard input.isDescendant(of: scrollView) else { return }

        if let note = keyboardNote {
            applyKeyboardInsets(from: note)
        } else if keyboardBottomInset > 0 {
            applyStoredKeyboardInsets()
        }

        scrollView.layoutIfNeeded()

        let focusRect = focusRectForInput(input)
        let padding: CGFloat = isDeleteAccountInput(input) ? 36 : 20

        let visibleBottom = scrollView.contentOffset.y
            + scrollView.bounds.height
            - scrollView.adjustedContentInset.bottom
        let targetBottom = focusRect.maxY + padding
        guard targetBottom > visibleBottom else { return }

        var newOffsetY = targetBottom - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        let maxOffsetY = max(
            -scrollView.adjustedContentInset.top,
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        )
        newOffsetY = min(max(newOffsetY, -scrollView.adjustedContentInset.top), maxOffsetY)

        let duration = (keyboardNote?.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?
            .doubleValue ?? 0.25
        let curveRaw = (keyboardNote?.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?
            .uintValue ?? UIView.AnimationOptions.curveEaseInOut.rawValue
        let options = UIView.AnimationOptions(rawValue: curveRaw << 16)

        let applyOffset = {
            self.scrollView.contentOffset = CGPoint(x: self.scrollView.contentOffset.x, y: newOffsetY)
        }

        if animated {
            UIView.animate(withDuration: duration, delay: 0, options: [options, .beginFromCurrentState], animations: applyOffset)
        } else {
            applyOffset()
        }
    }

    // MARK: - UITextFieldDelegate

    func textFieldDidBeginEditing(_ textField: UITextField) {
        scrollInputIntoView(textField, animated: false)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scrollInputIntoView(textField, animated: true)
        }
        guard isDeleteAccountInput(textField) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, textField.isFirstResponder else { return }
            self.scrollInputIntoView(textField, animated: true)
        }
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard textField === displayNameField else { return true }
        let next = (textField.text as NSString?)?.replacingCharacters(in: range, with: string) ?? string
        return next.count <= ProfileEditDefaults.displayNameCharacterLimit
    }

    // MARK: - UITextViewDelegate

    func textViewDidBeginEditing(_ textView: UITextView) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scrollInputIntoView(textView, animated: true)
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        guard textView === bioTextView else { return }
        if textView.text.count > ProfileEditDefaults.bioCharacterLimit {
            textView.text = String(textView.text.prefix(ProfileEditDefaults.bioCharacterLimit))
        }
        refreshBioCount()
    }

    private func refreshBioCount() {
        let n = bioTextView.text.count
        bioCountLabel.text = "\(n)/\(ProfileEditDefaults.bioCharacterLimit) characters"
    }
}

// MARK: - Scroll view helper

private extension UIScrollView {
    var firstResponderSubview: UIView? {
        func search(_ view: UIView) -> UIView? {
            if view.isFirstResponder { return view }
            for subview in view.subviews {
                if let match = search(subview) { return match }
            }
            return nil
        }
        return search(self)
    }
}

// MARK: - Camera / library pickers

extension ProfileEditViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true)
        let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        if let image {
            handlePickedProfileImage(image)
        }
    }
}

// MARK: - PHPicker

extension ProfileEditViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let item = results.first?.itemProvider, item.canLoadObject(ofClass: UIImage.self) else { return }
        item.loadObject(ofClass: UIImage.self) { [weak self] obj, _ in
            guard let image = obj as? UIImage else { return }
            DispatchQueue.main.async {
                self?.handlePickedProfileImage(image)
            }
        }
    }
}
