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
    /// needs a day after they were saved.
    func sync(_ state: FamilySnapshot, credential: FamilyCredential) {
        var wanted: [String: [String: Any]] = [:]
        if state.me.role == .bedside {
            for person in state.people { if let id = person.photoID { wanted[id] = ["memberID": person.id] } }
        } else if let id = state.me.photoID { wanted[id] = [:] }
        for (id, values) in wanted { load(id, values: values, credential: credential) }
        var keep = Set(wanted.keys).union([state.me.profile?.photoID].compactMap { $0 })
        // A key keeps the previous photo until the new one has downloaded, and a removed member's
        // photo until the caregiver edits that key. Those files are not in `wanted`, so keep them.
        if state.me.role == .bedside, let slots = try? CallSlots.load() {
            for contact in slots.contacts { if let id = contact?.memberPhotoID { keep.insert(id) } }
        }
        if keep != kept { kept = keep; store.prune(keeping: keep) }
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

/// A family phone's settings, opened from its photo: the name and photo the bedside shows for this phone, its calls,
/// and, less often, caregiver mode and changing family or device. The bedside shows the name and photo when this
/// phone calls, drops in or sends a message, unless a caregiver chose others.
final class FamilyProfileViewController: CaregiverFormViewController {
    private let content = UIStackView()
    /// Kept across redraws, which happen whenever anything in the family changes.
    private let nameField = UITextField()
    private var editedName: String?
    private var renderAfterEditing = false
    private var saving = false
    /// What the page shows from the family. Porch checks in every few seconds, and redrawing for a check-in that
    /// changed none of it would close an open photo menu and send VoiceOver back to the top.
    private struct Shown: Equatable {
        let paired: Bool
        /// This phone's own details the page shows. Being online or able to ring isn't one of them.
        let name: String?, invitedName: String?, profile: FamilyProfile?, override: FamilyProfile?, caregiver: Bool?
        let household: String?
        let lovedOne: String
        let photo: Bool
    }
    private var shown: Shown?
    private lazy var chooser = PhotoChooser(presenter: self) { [weak self] data in
        guard let self else { return }
        guard let data else { showPorchError(FamilyServiceError(message: "That photo couldn't be opened. Please choose another photo.", status: 400), on: self); return }
        self.saveProfile(["photo": data])
    }
    private var me: FamilyPerson? { FamilyCoordinator.shared.state?.me }
    private var lovedOne: String {
        let state = FamilyCoordinator.shared.state
        return state?.people.first { $0.role == .bedside }?.name ?? state?.householdName ?? "your loved one"
    }
    private var device: String { UIDevice.current.userInterfaceIdiom == .phone ? "iPhone" : "iPad" }

    override func viewDidLoad() {
        super.viewDidLoad(); title = "Settings"
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
        // Waits while the name is typed, so the keyboard doesn't close.
        guard !nameField.isFirstResponder else { renderAfterEditing = true; return }
        let paired = PorchDevice.credential(for: .family) != nil
        let photoID = me?.profile?.photoID
        let photo = photoID.map { FamilyPhotos.shared.store.contains($0) } == true
        // A new phone, or a photo saved elsewhere: download it, and try again on later check-ins if that fails.
        if !photo, let photoID, let credential = PorchDevice.credential(for: .family) {
            FamilyPhotos.shared.load(photoID, values: ["source": "self"], credential: credential)
        }
        let next = Shown(paired: paired, name: me?.name, invitedName: me?.invitedName, profile: me?.profile, override: me?.override, caregiver: me?.caregiver,
                         household: FamilyCoordinator.shared.state?.householdName, lovedOne: lovedOne, photo: photo)
        guard next != shown else { return }
        shown = next
        content.arrangedSubviews.forEach { content.removeArrangedSubview($0); $0.removeFromSuperview() }
        // The name is the only thing to type, so the keyboard choice shows only with it.
        setKeyboardControlVisible(paired && me != nil)
        if paired, let me { profile(me) } else if paired { content.addArrangedSubview(PorchStyle.label("Connecting to your family…")) }
        if paired {
            let camera = UISwitch(); camera.isOn = CallPreferences.startVideoWithCamera()
            camera.accessibilityIdentifier = "family.startVideoWithCamera"
            camera.addAction(UIAction { [weak camera] _ in if let camera { CallPreferences.saveStartVideoWithCamera(camera.isOn) } }, for: .valueChanged)
            content.addArrangedSubview(group(rows: [toggleRow("Start video calls with my camera on", camera)]))
        }
        if me?.caregiver == true {
            let caregiver = linkRow("Caregiver mode", symbol: "lock.fill") { [weak self] in
                self?.navigationController?.pushViewController(RemoteCaregiverPINViewController(), animated: true)
            }
            caregiver.accessibilityIdentifier = "family.caregiverMode"
            content.addArrangedSubview(group(rows: [caregiver]))
        }
        // Rarely needed, so they're links rather than settings.
        let links = UIStackView(arrangedSubviews: (paired ? [textLink("Join a different family") { [weak self] in self?.confirmNewFamily() }] : [])
            + [textLink("Use this \(device) as the bedside Porch") { [weak self] in self?.confirmBedside() }])
        links.axis = .vertical; links.alignment = .leading
        content.addArrangedSubview(links)
        let privacy = textLink("Privacy policy", size: 15) { [weak self] in if let self { showPrivacyPolicy(on: self) } }
        privacy.accessibilityIdentifier = "family.privacy"
        content.addArrangedSubview(privacy)
    }
    private func profile(_ me: FamilyPerson) {
        let photo = FamilyPhotos.shared.data(for: me.profile?.photoID)
        let change = PorchStyle.button(photo == nil ? "Add a photo" : "Change photo", filled: false)
        change.accessibilityIdentifier = "profile.choosePhoto"
        chooser.attach(to: change)
        var header: [UIView] = [FamilyAdminViewController.avatar(me.profile?.name ?? me.name, photo: photo, size: 96), change]
        if photo != nil {
            let remove = PorchStyle.button("Remove photo", filled: false)
            remove.configuration?.baseForegroundColor = .systemRed
            remove.addAction(UIAction { [weak self] _ in self?.saveProfile(["photo": NSNull()]) }, for: .touchUpInside)
            header.append(remove)
        }
        let household = PorchStyle.label(FamilyCoordinator.shared.state?.householdName ?? "", size: 15)
        household.textAlignment = .center
        header.append(household)
        let top = UIStackView(arrangedSubviews: header)
        top.axis = .vertical; top.alignment = .center; top.spacing = 2
        top.setCustomSpacing(10, after: header[0])
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
        guard !saving, let credential = PorchDevice.credential(for: .family) else { return }
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
    private func confirmNewFamily() {
        let current = FamilyCoordinator.shared.state?.householdName ?? "your current family"
        let alert = UIAlertController(title: "Join a different family?", message: "You'll need an invitation from that family's caregiver. Until you join, this \(device) stays in \(current).", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Continue", style: .default) { [weak self] _ in
            self?.navigationController?.pushViewController(FamilyPairingViewController(), animated: true)
        })
        present(alert, animated: true)
    }
    private func confirmBedside() {
        let alert = UIAlertController(title: "Use this \(device) as the bedside Porch?", message: "Only do this on the device next to your loved one. You can switch back later.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Use as bedside", style: .default) { _ in PorchDevice.experience = .bedside })
        present(alert, animated: true)
    }
}
