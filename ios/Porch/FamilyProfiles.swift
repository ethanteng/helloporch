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

/// The family member's own name and photo. The bedside shows them when they call, drop in or send a
/// message, unless a caregiver chose a name or photo for them.
final class FamilyProfileViewController: CaregiverFormViewController {
    private let nameField = UITextField()
    private let photoView = RecipientAppearance.photoView(nil)
    private let photoButton = PorchStyle.button("Add a photo", symbol: "camera", filled: false)
    private let removePhotoButton = PorchStyle.button("Remove photo", filled: false)
    private let note = PorchStyle.label("", size: 16, color: PorchStyle.accent, weight: .medium)
    private let connecting = PorchStyle.label("Connecting to your family…")
    private var built = false
    private var photo: Data?
    private var photoChanged = false
    private var saveTask: Task<Void, Never>?
    private lazy var chooser = PhotoChooser(presenter: self) { [weak self] data in
        guard let self else { return }
        guard let data else { showPorchError(FamilyServiceError(message: "That photo couldn't be opened. Please choose another photo.", status: 400), on: self); return }
        self.photo = data; self.photoChanged = true; self.updatePhoto()
    }
    private var me: FamilyPerson? { FamilyCoordinator.shared.state?.me }
    private var lovedOne: String {
        let state = FamilyCoordinator.shared.state
        return state?.people.first { $0.role == .bedside }?.name ?? state?.householdName ?? "your loved one"
    }

    override func viewDidLoad() {
        super.viewDidLoad(); title = "Your profile"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(save))
        form.addArrangedSubview(connecting)
        NotificationCenter.default.addObserver(self, selector: #selector(familyChanged), name: .porchFamilyChanged, object: nil)
        build()
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    /// Waits for this phone's details, which a just-opened Porch may still be loading.
    private func build() {
        guard !built else { return }
        guard let me else { navigationItem.rightBarButtonItem?.isEnabled = false; return }
        built = true; navigationItem.rightBarButtonItem?.isEnabled = true
        form.removeArrangedSubview(connecting); connecting.removeFromSuperview()
        let invited = me.invitedName ?? me.name
        nameField.text = me.profile?.name
        nameField.autocapitalizationType = .words
        nameField.textContentType = .name
        nameField.accessibilityIdentifier = "profile.name"
        photoView.contentMode = .scaleAspectFill
        photoView.layer.cornerRadius = 90
        NSLayoutConstraint.activate([photoView.widthAnchor.constraint(equalToConstant: 180), photoView.heightAnchor.constraint(equalToConstant: 180)])
        let photoRow = UIStackView(arrangedSubviews: [photoView]); photoRow.alignment = .center; photoRow.axis = .vertical
        photoButton.accessibilityIdentifier = "profile.choosePhoto"
        chooser.attach(to: photoButton)
        removePhotoButton.configuration?.baseForegroundColor = .systemRed
        removePhotoButton.addAction(UIAction { [weak self] _ in self?.photo = nil; self?.photoChanged = true; self?.updatePhoto() }, for: .touchUpInside)
        let helper = "Leave blank to use “\(invited)”, the name on your invitation."
        form.addArrangedSubview(section("How \(lovedOne) sees you", detail: "\(lovedOne) sees your name and photo when you call or send a message.",
            views: [photoRow, photoButton, removePhotoButton, field(nameField, title: "Your name", placeholder: invited, helper: helper)]))
        note.textAlignment = .center
        form.addArrangedSubview(note)
        form.addArrangedSubview(PorchStyle.label("A caregiver can change these for you.", size: 15))
        updateNote()
        photo = FamilyPhotos.shared.data(for: me.profile?.photoID)
        updatePhoto()
        // A new phone, or a photo saved elsewhere: download it once.
        if photo == nil, let id = me.profile?.photoID, let credential = PorchDevice.credential(for: .family) {
            FamilyPhotos.shared.load(id, values: ["source": "self"], credential: credential)
        }
    }
    @objc private func familyChanged() {
        guard built else { build(); return }
        updateNote()
        if !photoChanged, photo == nil, let data = FamilyPhotos.shared.data(for: me?.profile?.photoID) { photo = data; updatePhoto() }
    }
    private func updatePhoto() {
        photoView.image = RecipientAppearance.photo(photo)
        photoView.isHidden = photo == nil
        removePhotoButton.isHidden = photo == nil
        photoButton.configuration?.title = photo == nil ? "Add a photo" : "Change photo"
    }
    private func updateNote() {
        let chosen = me?.override
        switch (chosen?.name, chosen?.photoID != nil) {
        case let (name?, true): note.text = "A caregiver set your name to “\(name)” and chose your photo. \(lovedOne) sees those."
        case let (name?, false): note.text = "A caregiver set your name to “\(name)”. \(lovedOne) sees that name."
        case (nil, true): note.text = "A caregiver chose your photo. \(lovedOne) sees that photo."
        default: note.text = nil
        }
        note.isHidden = note.text == nil
    }
    @objc private func save() {
        guard built, saveTask == nil, let credential = PorchDevice.credential(for: .family) else { return }
        view.endEditing(true)
        navigationItem.rightBarButtonItem?.isEnabled = false; navigationItem.rightBarButtonItem?.title = "Saving…"
        saveTask = Task { [weak self] in
            guard let self else { return }
            defer { self.saveTask = nil; self.navigationItem.rightBarButtonItem?.isEnabled = true; self.navigationItem.rightBarButtonItem?.title = "Save" }
            do {
                var values: [String: Any] = ["name": self.nameField.text ?? ""]
                if self.photoChanged {
                    if let photo = self.photo { values["photo"] = try await FamilyPhotos.shared.upload(photo, action: "profilePhotoUpload", credential: credential) }
                    else { values["photo"] = NSNull() }
                }
                let response = try await FamilyService(credential).send("setProfile", values)
                FamilyCoordinator.shared.update(response)
                self.navigationController?.popViewController(animated: true)
            } catch { if !Task.isCancelled { showPorchError(error, on: self) } }
        }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent { saveTask?.cancel() }
    }
}
