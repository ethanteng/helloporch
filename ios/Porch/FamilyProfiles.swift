import UIKit
import PhotosUI
import UniformTypeIdentifiers
import PorchCore

/// A short-lived link to a family member's photo, with the content ID its bytes must match.
struct ProfilePhotoURL: Decodable { let id: String; let url: String; let expiresAt: TimeInterval }

/// Family members' photos from Porch, saved on this device under their content ID (the SHA-256 of
/// the JPEG). The bedside keeps everyone's current photo for keypad cards, calls and messages; a
/// family phone keeps its own.
@MainActor final class FamilyPhotos {
    static let shared = FamilyPhotos()
    let store = ContactPhotoStore.standard.familyMembers
    private var loading: Set<String> = []
    private var retryAfter: [String: Date] = [:]
    private var kept: Set<String>?

    func data(for id: String?) -> Data? { id.flatMap { store.data(for: $0) } }
    /// The photo Porch shows for a paired family member, on the bedside.
    func photo(forMember id: String) -> Data? { data(for: FamilyCoordinator.shared.state?.people.first { $0.id == id }?.photoID) }

    /// Called with every snapshot: downloads photos this device shows, and deletes ones it no longer
    /// needs a day after they were saved. A phone in several families keeps its photo in each of them, so nothing is
    /// deleted until every family has checked in.
    func sync(_ families: [(state: FamilySnapshot, credential: FamilyCredential)], everyFamily: Bool) {
        var keep = Set<String>()
        for (state, credential) in families {
            var wanted: [String: [String: Any]] = [:]
            if state.me.role == .bedside {
                for person in state.people { if let id = person.photoID { wanted[id] = ["memberID": person.id] } }
            } else if let id = state.me.photoID { wanted[id] = [:] }
            for (id, values) in wanted { load(id, values: values, credential: credential) }
            keep.formUnion(Set(wanted.keys).union([state.me.profile?.photoID].compactMap { $0 }))
            // A key keeps the previous photo until the new one has downloaded, and a removed member's
            // photo until the caregiver edits that key. Those files are not in `wanted`, so keep them.
            if state.me.role == .bedside, let slots = try? CallSlots.load() {
                for contact in slots.contacts { if let id = contact?.memberPhotoID { keep.insert(id) } }
            }
        }
        if everyFamily, !families.isEmpty, keep != kept { kept = keep; store.prune(keeping: keep) }
    }

    /// Starts downloading a photo unless it's already here, downloading, or failed in the last minute.
    /// Snapshot observers refresh once it's saved.
    func load(_ id: String, action: String = "profilePhoto", values: [String: Any] = [:], credential: FamilyCredential, pin: String? = nil) {
        guard !store.contains(id), !loading.contains(id), (retryAfter[id] ?? .distantPast) < Date() else { return }
        loading.insert(id)
        Task {
            defer { loading.remove(id) }
            do {
                let response = try await FamilyService(credential).send(action, values, pin: pin)
                guard let photo = response.photo, let url = URL(string: photo.url) else { throw FamilyServiceError(message: "This photo isn't available.", status: 404) }
                let session = URLSession(configuration: .ephemeral)
                defer { session.invalidateAndCancel() }
                let (data, download) = try await session.data(from: url)
                // The server can't see inside the photo, so the device that shows it checks it.
                guard (download as? HTTPURLResponse)?.statusCode == 200, ContactPhotoStore.id(for: data) == photo.id else {
                    throw FamilyServiceError(message: "This photo couldn't be downloaded.", status: 502)
                }
                try store.add(data)
                FamilyCoordinator.shared.photoLoaded()
            } catch { retryAfter[id] = Date().addingTimeInterval(60) }
        }
    }

    /// Uploads a photo and returns the reference `setProfile` or `setMemberOverride` saves.
    func upload(_ data: Data, action: String, values: [String: Any] = [:], credential: FamilyCredential, pin: String? = nil) async throws -> [String: String] {
        var values = values; values["sizeBytes"] = data.count
        let created = try await FamilyService(credential).send(action, values, pin: pin)
        guard let target = created.upload, let pathname = created.pathname, let url = URL(string: target.url) else {
            throw FamilyServiceError(message: "Couldn't upload the photo. Try again.", status: 503)
        }
        var request = URLRequest(url: url)
        request.httpMethod = target.method; request.timeoutInterval = 120
        for (field, value) in target.headers { request.setValue(value, forHTTPHeaderField: field) }
        let (_, response) = try await URLSession.shared.upload(for: request, from: data)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw FamilyServiceError(message: "The photo didn't upload. Check the connection and try again.", status: status, code: "upload") }
        try? store.add(data)
        return ["id": ContactPhotoStore.id(for: data), "pathname": pathname]
    }
}

/// Takes a photo or chooses one from the library, prepared like keypad photos: upright, at most
/// 768 pixels and under 1 MB. `completion` gets nil when the photo couldn't be opened.
final class PhotoChooser: NSObject, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private weak var presenter: UIViewController?
    private let completion: (Data?) -> Void
    init(presenter: UIViewController, completion: @escaping (Data?) -> Void) {
        self.presenter = presenter; self.completion = completion
    }
    var menu: UIMenu {
        var actions = [UIAction(title: "Choose from library", image: UIImage(systemName: "photo.on.rectangle")) { [weak self] _ in self?.chooseFromLibrary() }]
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            actions.insert(UIAction(title: "Take photo", image: UIImage(systemName: "camera")) { [weak self] _ in self?.takePhoto() }, at: 0)
        }
        return UIMenu(children: actions)
    }
    /// Shows the choices when the button is tapped.
    func attach(to button: UIButton) { button.menu = menu; button.showsMenuAsPrimaryAction = true }

    private func chooseFromLibrary() {
        presenter?.view.endEditing(true)
        var configuration = PHPickerConfiguration()
        configuration.filter = .images; configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        presenter?.present(picker, animated: true)
    }
    private func takePhoto() {
        presenter?.view.endEditing(true)
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        if UIImagePickerController.isCameraDeviceAvailable(.front) { picker.cameraDevice = .front }
        picker.delegate = self
        presenter?.present(picker, animated: true)
    }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, _ in
            let data = url.flatMap { RecipientAppearance.preparedPhoto(at: $0) }
            DispatchQueue.main.async { self?.completion(data) }
        }
    }
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        let data = (info[.originalImage] as? UIImage).flatMap { RecipientAppearance.preparedPhoto($0) }
        completion(data)
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) }
}

/// What the bedside shows for this phone in one family, opened from that family's page: its name and photo, shown when
/// this phone calls, drops in or sends a message, unless a caregiver chose others. Each family has its own, so the page
/// is for the family chosen last, which the family's page chooses.
final class FamilyProfileViewController: CaregiverFormViewController {
    /// The family this page was opened for. You can switch families while this stays open on its own tab, and a name typed here must stay with this one.
    private let family: FamilyCredential?
    private let content = UIStackView()
    /// Kept across redraws, which happen whenever anything in the family changes.
    private let nameField = UITextField()
    private var editedName: String?
    private var renderAfterEditing = false
    private var saving = false
    /// What the page shows from the family. Porch checks in every few seconds, and redrawing for a check-in that
    /// changed none of it would close an open photo menu and send VoiceOver back to the top.
    private struct Shown: Equatable {
        /// This phone's own details the page shows. Being online or able to ring isn't one of them.
        let name: String?, invitedName: String?, profile: FamilyProfile?, override: FamilyProfile?
        let lovedOne: String
        let photo: Bool
    }
    private var shown: Shown?
    /// The family the form on screen was built for. A name typed for one family must not be saved onto another.
    private var formCredential: FamilyCredential?
    private lazy var chooser = PhotoChooser(presenter: self) { [weak self] data in
        guard let self else { return }
        guard let data else { showPorchError(FamilyServiceError(message: "That photo couldn't be opened. Please choose another photo.", status: 400), on: self); return }
        self.saveProfile(["photo": data])
    }
    init(family: FamilyCredential? = nil) {
        self.family = family ?? PorchDevice.credential(for: .family)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(family:)") }
    /// Nil only when the page was opened with no family yet, in which case it follows the one chosen last.
    private var credential: FamilyCredential? { family ?? PorchDevice.currentFamily }
    private var snapshot: FamilySnapshot? { credential.flatMap { FamilyCoordinator.shared.state(for: $0) } }
    private var me: FamilyPerson? { snapshot?.me }
    private var lovedOne: String {
        snapshot?.people.first { $0.role == .bedside }?.name ?? snapshot?.householdName ?? "your loved one"
    }

    override func viewDidLoad() {
        super.viewDidLoad(); title = "Your name and photo"
        content.axis = .vertical; content.spacing = 24
        form.addArrangedSubview(content)
        nameField.textContentType = .name
        nameField.accessibilityIdentifier = "profile.name"
        nameField.addAction(UIAction { [weak self] _ in self?.editedName = self?.nameField.text }, for: .editingChanged)
        NotificationCenter.default.addObserver(self, selector: #selector(render), name: .porchFamilyChanged, object: nil)
        render()
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func textFieldDidEndEditing(_ textField: UITextField) {
        super.textFieldDidEndEditing(textField)
        if renderAfterEditing { renderAfterEditing = false; render() }
    }
    @objc private func render() {
        guard isViewLoaded else { return }
        // Waits while a name is typed, so the keyboard doesn't close.
        guard !nameField.isFirstResponder else { renderAfterEditing = true; return }
        let current = credential
        // An unpinned page follows a family chosen meanwhile, and drops a half-typed name. This page is for one family.
        if family == nil, current?.deviceID != formCredential?.deviceID { editedName = nil }
        let photoID = me?.profile?.photoID
        let photo = photoID.map { FamilyPhotos.shared.store.contains($0) } == true
        // A new phone, or a photo saved elsewhere: download it, and try again on later check-ins if that fails.
        if !photo, let photoID, let current {
            FamilyPhotos.shared.load(photoID, values: ["source": "self"], credential: current)
        }
        let next = Shown(name: me?.name, invitedName: me?.invitedName, profile: me?.profile, override: me?.override, lovedOne: lovedOne, photo: photo)
        guard next != shown else { return }
        shown = next
        formCredential = current
        content.arrangedSubviews.forEach { content.removeArrangedSubview($0); $0.removeFromSuperview() }
        setKeyboardControlVisible(me != nil)
        if let me { profile(me) } else { content.addArrangedSubview(PorchStyle.label("Connecting to your family…")) }
    }
    private func profile(_ me: FamilyPerson) {
        let photo = FamilyPhotos.shared.data(for: me.profile?.photoID)
        let change = PorchStyle.button(photo == nil ? "Add a photo" : "Change photo", filled: false)
        change.accessibilityIdentifier = "profile.choosePhoto"
        chooser.attach(to: change)
        var actions = [change]
        if photo != nil {
            let remove = PorchStyle.button("Remove photo", filled: false)
            remove.configuration?.baseForegroundColor = .systemRed
            remove.addAction(UIAction { [weak self] _ in self?.saveProfile(["photo": NSNull()]) }, for: .touchUpInside)
            actions.append(remove)
        }
        let top = UIStackView(arrangedSubviews: [FamilyAdminViewController.avatar(me.profile?.name ?? me.name, photo: photo, size: 96), PorchStyle.photoActions(actions)])
        top.axis = .vertical; top.alignment = .center; top.spacing = 10
        content.addArrangedSubview(top)
        nameField.text = editedName ?? me.profile?.name
        let save = PorchStyle.button("Save", symbol: "checkmark")
        save.accessibilityLabel = "Save name"
        save.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.view.endEditing(true)
            self.saveProfile(["name": self.nameField.text ?? ""])
        }, for: .touchUpInside)
        let invited = me.invitedName ?? me.name
        let name = field(nameField, title: "Name", placeholder: invited)
        // `field` resets capitalization, including on every redraw of this page.
        nameField.autocapitalizationType = .words
        let nameRow = listRow(name, trailing: FamilyAdminViewController.singleLine(save), alignedToBottom: true)
        // A caregiver's choice is what the bedside shows, which would otherwise be a surprise.
        let chosen = me.override
        let note: String?
        switch (chosen?.name, chosen?.photoID != nil) {
        case let (name?, true): note = "A caregiver set your name to “\(name)” and chose your photo. \(lovedOne) sees those."
        case let (name?, false): note = "A caregiver set your name to “\(name)”. \(lovedOne) sees that name."
        case (nil, true): note = "A caregiver chose your photo. \(lovedOne) sees that photo."
        default: note = nil
        }
        content.addArrangedSubview(group(detail: note, rows: [nameRow]))
    }
    /// Saves a new name or photo: a photo is uploaded first, and NSNull removes it.
    private func saveProfile(_ change: [String: Any]) {
        guard !saving, let credential = formCredential ?? PorchDevice.credential(for: .family) else { return }
        saving = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.saving = false }
            do {
                var values = change
                if let photo = change["photo"] as? Data { values["photo"] = try await FamilyPhotos.shared.upload(photo, action: "profilePhotoUpload", credential: credential) }
                let response = try await FamilyService(credential).send("setProfile", values)
                if change["name"] != nil { self.editedName = nil }
                FamilyCoordinator.shared.update(response)
                self.render()
            } catch { showPorchError(error, on: self) }
        }
    }
}

/// Group keys show their people's photos, which only the family app keeps (the keypad preview has none).
extension RecipientAppearance {
    /// A group key without a photo of its own shows its people's photos side by side, each half filled, and the initial
    /// of anyone without one. Nil when neither has a photo, so the key reads like a person without one.
    @MainActor static func groupPhoto(_ group: CallGroup) -> Data? {
        let photos = group.memberIDs.map { FamilyPhotos.shared.photo(forMember: $0).flatMap(UIImage.init(data:)) }
        guard photos.contains(where: { $0 != nil }) else { return nil }
        let side: CGFloat = 480
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let width = side / CGFloat(photos.count)
            for (index, photo) in photos.enumerated() {
                let frame = CGRect(x: CGFloat(index) * width, y: 0, width: width, height: side)
                context.cgContext.saveGState()
                UIBezierPath(rect: frame).addClip()
                if let photo {
                    let scale = max(frame.width / photo.size.width, frame.height / photo.size.height)
                    let scaled = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
                    photo.draw(in: CGRect(x: frame.midX - scaled.width / 2, y: frame.midY - scaled.height / 2, width: scaled.width, height: scaled.height))
                } else {
                    PorchStyle.nightSurface.setFill(); UIRectFill(frame)
                    let initial = (group.memberNames[index].first.map { String($0).uppercased() } ?? "") as NSString
                    let attributes: [NSAttributedString.Key: Any] = [.font: PorchStyle.systemFont(side * 0.3, weight: .semibold), .foregroundColor: UIColor.white]
                    let size = initial.size(withAttributes: attributes)
                    initial.draw(at: CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2), withAttributes: attributes)
                }
                context.cgContext.restoreGState()
            }
            // A thin line between the two halves.
            UIColor.white.withAlphaComponent(0.85).setFill()
            for index in 1..<photos.count { UIRectFill(CGRect(x: CGFloat(index) * width - 2, y: 0, width: 4, height: side)) }
        }
        return image.jpegData(compressionQuality: 0.85)
    }
    /// A group key as the bedside shows and calls it: its name, color, and its photo or its people's.
    @MainActor static func groupContact(_ group: CallGroup) -> CallContact {
        guard group.photoData == nil, let photo = groupPhoto(group) else { return group.callContact }
        return (try? group.callContact.updating(photoData: .some(photo))) ?? group.callContact
    }
}
