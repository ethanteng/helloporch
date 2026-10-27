import UIKit
import AVFoundation
import PorchCore

extension Notification.Name {
    /// Caregiver settings changed, here or from another caregiver. The object is the `FamilyAdminViewController` they belong to.
    static let porchCaregiverChanged = Notification.Name("porch.caregiver.changed")
}

/// Caregiver settings, by what they're about. The bedside has every page. Caregiver mode on a family phone has the
/// ones kept on the server, and lists the rest as set on the bedside.
enum CaregiverPage: String, CaseIterable {
    case people, calls, dropIn, messages, display, privacy, caregivers, device

    static func pages(onBedside: Bool) -> [CaregiverPage] {
        onBedside ? allCases : [.people, .calls, .dropIn, .messages, .privacy, .caregivers]
    }
    func title(onBedside: Bool) -> String {
        switch self {
        case .people: return onBedside ? "People" : "Family"
        case .calls: return "Calls"
        case .dropIn: return "Drop-in"
        case .messages: return "Messages"
        case .display: return "Display & voice"
        case .privacy: return "Privacy"
        case .caregivers: return onBedside ? "Caregivers & PIN" : "Caregivers"
        case .device: return UIDevice.current.userInterfaceIdiom == .phone ? "This iPhone" : "This iPad"
        }
    }
    var symbol: String {
        switch self {
        case .people: return "person.2.fill"
        case .calls: return "phone.fill"
        case .dropIn: return "waveform"
        case .messages: return "envelope.fill"
        case .display: return "sun.and.horizon.fill"
        case .privacy: return "hand.raised.fill"
        case .caregivers: return "lock.fill"
        case .device: return UIDevice.current.userInterfaceIdiom == .phone ? "iphone" : "ipad"
        }
    }
}

/// Caregiver mode on a bedside iPad: the list of pages beside the one that's open.
final class CaregiverSplitViewController: UISplitViewController, UISplitViewControllerDelegate {
    init(home: FamilyAdminViewController) {
        super.init(style: .doubleColumn)
        delegate = self
        overrideUserInterfaceStyle = .light
        modalPresentationStyle = .fullScreen
        preferredDisplayMode = .oneBesideSecondary
        preferredSplitBehavior = .tile
        displayModeButtonVisibility = .never
        presentsWithGesture = false
        preferredPrimaryColumnWidthFraction = 0.34
        minimumPrimaryColumnWidth = 280
        maximumPrimaryColumnWidth = 360
        home.currentPage = .people
        setViewController(PorchStyle.navigation(home), for: .primary)
        setViewController(PorchStyle.navigation(home.controller(for: .people)), for: .secondary)
    }
    required init?(coder: NSCoder) { fatalError("Use init(home:)") }
    /// A narrow window starts from the list, as on a phone.
    func splitViewController(_ svc: UISplitViewController, topColumnForCollapsingToProposedTopColumn proposedTopColumn: UISplitViewController.Column) -> UISplitViewController.Column { .primary }
}

/// Caregiver mode's home: who this Porch is for, and the settings pages. On a bedside iPad it's the sidebar beside the
/// open page. It also keeps the household as caregiver mode sees it, and makes every change, for the pages it opens.
final class FamilyAdminViewController: CaregiverFormViewController {
    /// Set when caregiver mode was opened from a family phone; nil on the bedside.
    let remote: FamilyCredential?
    private var remoteState: FamilyAdminState?
    /// The bedside's keypad, which only the bedside can change. Nil in caregiver mode on a family phone.
    private(set) var slots: CallSlots?
    /// Saves a changed keypad on the bedside.
    var onSaveSlots: ((CallSlots) throws -> Void)?
    /// The page beside this list, while they're side by side.
    var currentPage: CaregiverPage?
    private let list = UIStackView()
    private var busy = false
    private var appeared = false
    private var locked = false
    private var displayed: FamilyAdminState?
    /// Family photos on this device when the pages were last drawn, so one that finishes downloading is shown.
    private var displayedPhotos: Set<String> = []
    private var wasBeside: Bool?
    private var credential: FamilyCredential? { remote ?? PorchDevice.credential(for: .bedside) }
    var onBedside: Bool { remote == nil }
    var myID: String? { credential?.credential.split(separator: ".").first.map { String($0) } }
    var current: FamilyAdminState? {
        if remote != nil { return remoteState }
        return FamilyCoordinator.shared.state.map { FamilyAdminState(householdName: $0.householdName, dropInEnabled: $0.dropInEnabled, people: $0.people.filter { $0.role == .family }, messagesEnabled: $0.messagesEnabled, messages: $0.messages, phoneDropIns: $0.phoneDropIns, invitations: $0.invitations, callScreening: $0.callScreening, shareAttendance: $0.shareAttendance) }
    }
    /// The bedside's name for headings, such as Calls to Mom.
    var lovedOne: String { current?.householdName ?? "your loved one" }
    init(remote: FamilyCredential? = nil, state: FamilyAdminState? = nil, slots: CallSlots? = nil) {
        self.remote = remote; remoteState = state
        self.slots = remote == nil ? slots ?? (try? CallSlots.load()) : nil
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(remote:state:slots:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Caregiver mode"
        hideKeyboardControl()
        navigationItem.rightBarButtonItem = remote == nil
            ? UIBarButtonItem(title: "Back to clock", style: .done, target: self, action: #selector(backToClock))
            : UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(leaveCaregiverMode))
        list.axis = .vertical; list.spacing = 24
        form.addArrangedSubview(list)
        NotificationCenter.default.addObserver(self, selector: #selector(familyChanged), name: .porchFamilyChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(returnedToForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        refresh()
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func familyChanged() {
        if remote != nil {
            // Polls every few seconds: withdrawn approval, a removed device or the idle timeout locks right away.
            let coordinator = FamilyCoordinator.shared
            if coordinator.accessRemoved || coordinator.state?.me.caregiver == false {
                lock(FamilyServiceError(message: "Caregiver mode is no longer available on this phone.", status: 403))
            } else if !RemoteCaregiverSession.shared.isActive { lock(nil) }
            return
        }
        guard !busy else { return }
        if displayed != current || displayedPhotos != photosOnHand() { refresh() }
    }
    @objc private func returnedToForeground() { if remote != nil && !RemoteCaregiverSession.shared.isActive { lock(nil) } }
    @objc private func leaveCaregiverMode() { RemoteCaregiverSession.shared.end(); navigationController?.popToRootViewController(animated: true) }
    @objc private func backToClock() { view.endEditing(true); dismiss(animated: true) }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if remote == nil && PorchDevice.credential(for: .bedside) != nil { refresh() }
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        #if DEBUG
        preview()
        #endif
        guard remote != nil else { return }
        guard RemoteCaregiverSession.shared.isActive else { lock(nil); return }
        // The unlock already returned fresh details; later returns (from an invitation) reload them.
        if appeared || remoteState == nil { Task { await self.perform("verifyPIN") } }
        appeared = true
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if remote != nil && isMovingFromParent { RemoteCaregiverSession.shared.end() }
    }
    /// Marks the open page only while it's beside this list.
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        if wasBeside != isBeside { renderList() }
    }
    private var isBeside: Bool { splitViewController.map { !$0.isCollapsed } == true }
    /// Ends a phone's caregiver session and returns to family mode.
    private func lock(_ error: Error?) {
        RemoteCaregiverSession.shared.end()
        guard !locked, let navigation = navigationController, let home = navigation.viewControllers.first else { return }
        locked = true
        CATransaction.begin()
        CATransaction.setCompletionBlock { if let error { showPorchError(error, on: home) } }
        navigation.popToRootViewController(animated: true)
        CATransaction.commit()
    }
    private func photosOnHand() -> Set<String> {
        Set((current?.people ?? []).compactMap(\.photoID).filter { FamilyPhotos.shared.store.contains($0) })
    }
    /// Redraws this list and every open page.
    func refresh() {
        displayed = current
        displayedPhotos = photosOnHand()
        // Shows family members' current names and photos on their keys. Saving the keypad keeps them.
        if remote == nil, var updated = slots, let state = FamilyCoordinator.shared.state { try? updated.reconcile(with: state); slots = updated }
        renderList()
        NotificationCenter.default.post(name: .porchCaregiverChanged, object: self)
    }
    /// Takes the household as the server returned it with a change made on another screen.
    func adopt(_ state: FamilyAdminState?) {
        if remote != nil, let state { remoteState = state }
        refresh()
    }
    private func renderList() {
        wasBeside = isBeside
        list.arrangedSubviews.forEach { list.removeArrangedSubview($0); $0.removeFromSuperview() }
        // This iPad's own settings work before setup finishes; family settings need it.
        if credential == nil { list.addArrangedSubview(PorchStyle.label("Go back to the clock and open caregiver mode to finish setup.")) }
        let state = current
        let name = state?.householdName ?? "Your loved one"
        let household = PorchListRow([Self.avatar(name, size: 52), PorchStyle.label(name, size: 20, color: PorchStyle.ink, weight: .semibold)],
                                     label: "\(name). Change the name family see") { [weak self] in
            guard let self else { return }
            self.show(HouseholdNameViewController(admin: self))
        }
        household.accessibilityIdentifier = "caregiver.household"
        list.addArrangedSubview(group(rows: [household]))
        let rows = CaregiverPage.pages(onBedside: onBedside).map { page -> UIView in
            let row = linkRow(page.title(onBedside: onBedside), value: value(for: page, state), symbol: page.symbol) { [weak self] in self?.open(page) }
            row.accessibilityIdentifier = "caregiver.page.\(page.rawValue)"
            row.isCurrent = isBeside && page == currentPage
            return row
        }
        list.addArrangedSubview(group(rows: rows))
        guard remote != nil else { return }
        let bedsideOnly = ["Keypad", "Display & voice", "Caregiver PIN"].map { title -> UIView in
            let lock = UIImageView(image: UIImage(systemName: "lock.fill")); lock.tintColor = PorchStyle.secondary
            lock.contentMode = .scaleAspectFit
            lock.setContentHuggingPriority(.required, for: .horizontal)
            lock.widthAnchor.constraint(equalToConstant: 26).isActive = true
            let row = listRow([lock, PorchStyle.label(title, size: 18)])
            row.isAccessibilityElement = true; row.accessibilityLabel = "\(title), set on the bedside iPad"
            return row
        }
        list.addArrangedSubview(group("On the bedside iPad", rows: bedsideOnly))
    }
    /// What a page is set to, beside its name.
    private func value(for page: CaregiverPage, _ state: FamilyAdminState?) -> String? {
        guard let state else { return nil }
        switch page {
        case .people: return state.people.isEmpty ? nil : "\(state.people.count)"
        case .dropIn: return state.dropInEnabled ? "On" : "Off"
        case .messages:
            let waiting = state.messages ?? [], held = waiting.filter { $0.held == true }.count
            return held > 0 ? "\(held) need\(held == 1 ? "s" : "") OK" : !waiting.isEmpty ? "\(waiting.count) waiting" : state.messagesEnabled == false ? "Off" : nil
        case .caregivers:
            let count = state.people.filter { $0.caregiver == true }.count
            return count == 0 ? nil : "\(count)"
        case .calls, .display, .privacy, .device: return nil
        }
    }
    func controller(for page: CaregiverPage) -> UIViewController {
        switch page {
        case .people: return PeopleSettingsViewController(admin: self)
        case .calls: return CallSettingsViewController(admin: self)
        case .dropIn: return DropInSettingsViewController(admin: self)
        case .messages: return MessageSettingsViewController(admin: self)
        case .display: return BedsideDisplaySettingsViewController()
        case .privacy: return PrivacySettingsViewController(admin: self)
        case .caregivers: return CaregiverAccessViewController(admin: self)
        case .device: return DeviceSettingsViewController()
        }
    }
    /// Shows a page beside this list on a wide iPad, or on its own otherwise.
    func open(_ page: CaregiverPage) {
        let controller = controller(for: page)
        if let split = splitViewController, !split.isCollapsed {
            currentPage = page; renderList()
            split.setViewController(PorchStyle.navigation(controller), for: .secondary)
        } else { navigationController?.pushViewController(controller, animated: true) }
    }
    /// Opens a screen over the page beside this list, or from this list on a phone.
    func show(_ controller: UIViewController) {
        if let split = splitViewController, !split.isCollapsed, let detail = split.viewController(for: .secondary) as? UINavigationController ?? split.viewController(for: .secondary)?.navigationController {
            detail.pushViewController(controller, animated: true)
        } else { navigationController?.pushViewController(controller, animated: true) }
    }
    #if DEBUG
    private var previewed = false
    private func preview() {
        guard !previewed else { return }
        previewed = true
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--preview-caregiver-page"), args.indices.contains(index + 1), let page = CaregiverPage(rawValue: args[index + 1]) { open(page) }
        if let index = args.firstIndex(of: "--preview-caregiver-key"), args.indices.contains(index + 1), let digit = CallSlots.digit(forSymbol: args[index + 1]) {
            show(PersonViewController(admin: self, slot: digit))
        }
        if args.contains("--preview-family-person"), let person = current?.people.first { show(PersonViewController(admin: self, memberID: person.id)) }
    }
    #endif

    // MARK: Keypad

    /// Changes the keypad and saves it, keeping family members' current names and photos on their keys.
    func saveSlots(_ change: (inout CallSlots) throws -> Void) throws {
        guard var updated = slots else { return }
        try change(&updated)
        // Invites may be accepted while the caregiver is editing.
        if let state = FamilyCoordinator.shared.state { try updated.reconcile(with: state) }
        try onSaveSlots?(updated)
        slots = updated
        refresh()
    }
    /// The key that calls this family member, if any.
    func key(for person: FamilyPerson) -> Int? {
        CallSlots.digits.first { digit in slots?.contact(for: digit).map { Self.contact($0, isFor: person) } == true }
    }
    static func contact(_ contact: CallContact, isFor person: FamilyPerson) -> Bool {
        (contact.invitationID != nil && contact.invitationID == person.invitationID) || (contact.familyMemberID != nil && contact.familyMemberID == person.id)
    }

    // MARK: Changes

    /// Where an error shows: over whatever caregiver screen is open.
    private var presenter: UIViewController {
        var top: UIViewController = splitViewController ?? navigationController ?? self
        while let presented = top.presentedViewController, !presented.isBeingDismissed { top = presented }
        return top
    }
    func showError(_ error: Error) { showPorchError(error, on: presenter) }
    func requestMedia(video: Bool) async -> Bool {
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        let camera = video ? await AVCaptureDevice.requestAccess(for: .video) : true
        guard microphone && camera else {
            showError(FamilyServiceError(message: "Allow microphone\(video ? " and camera" : "") access in iPad Settings before enabling drop-in.", status: 403))
            return false
        }
        return true
    }
    /// The PIN for the next caregiver request; nil (and locked) once a phone's caregiver session has ended.
    func caregiverPIN() -> String? {
        guard remote != nil else { return NativeCallSettings.caregiverCode }
        guard let active = RemoteCaregiverSession.shared.activePIN else { lock(nil); return nil }
        return active
    }
    @discardableResult func perform(_ action: String, _ values: [String: Any] = [:]) async -> Bool {
        guard !busy, let credential, let pin = caregiverPIN() else { return false }
        busy = true; defer { busy = false }
        do {
            let response = try await FamilyService(credential).send(action, values, pin: pin)
            FamilyCoordinator.shared.update(response)
            if let admin = response.admin { remoteState = admin }
            refresh()
            return true
        } catch {
            // A changed PIN, withdrawn approval or lockout ends a phone's caregiver session.
            if remote != nil, let failure = error as? FamilyServiceError, [401, 403, 429].contains(failure.status) { lock(error); return false }
            refresh(); showError(error)
            return false
        }
    }
    /// Uploads a photo a caregiver chose for a family member, then shows it in place of theirs.
    @discardableResult func chooseOverridePhoto(_ data: Data, for memberID: String) async -> Bool {
        guard !busy, let credential, let pin = caregiverPIN() else { return false }
        busy = true
        let photo: [String: String]
        do { photo = try await FamilyPhotos.shared.upload(data, action: "overridePhotoUpload", values: ["memberID": memberID], credential: credential, pin: pin); busy = false }
        catch {
            busy = false
            if remote != nil, let failure = error as? FamilyServiceError, [401, 403, 429].contains(failure.status) { lock(error) }
            else { showError(error) }
            return false
        }
        return await perform("setMemberOverride", ["memberID": memberID, "photo": photo])
    }
    /// The bedside downloads everyone's photo itself; a caregiver's phone fetches one when it's shown.
    func loadPhoto(of person: FamilyPerson) {
        guard let remote, let id = person.photoID, !FamilyPhotos.shared.store.contains(id), let pin = RemoteCaregiverSession.shared.activePIN else { return }
        FamilyPhotos.shared.load(id, action: "caregiverProfilePhoto", values: ["memberID": person.id], credential: remote, pin: pin)
    }
    func inviteScreen() -> FamilyInviteViewController {
        let invite = FamilyInviteViewController(); invite.remote = remote
        invite.onAdminChanged = { [weak self] admin in self?.adopt(admin) }
        return invite
    }
    func phoneDropInScreen() -> PhoneDropInViewController {
        let approve = PhoneDropInViewController(); approve.remote = remote
        approve.onSaved = { [weak self] admin in self?.adopt(admin) }
        return approve
    }

    // MARK: Shared views

    /// Keeps a short trailing label or button on one line at its natural width.
    static func singleLine<View: UIView>(_ view: View) -> View {
        (view as? UILabel)?.numberOfLines = 1
        (view as? UIButton)?.titleLabel?.numberOfLines = 1
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        return view
    }
    /// Their photo, or initials, in a fixed circle. It never stretches, so a row's text column takes the spare width.
    static func avatar(_ name: String, photo: Data? = nil, size: CGFloat = 44) -> UIView {
        let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        let badge = circle(size: size)
        if let image = RecipientAppearance.photo(photo) {
            let view = UIImageView(image: image)
            view.contentMode = .scaleAspectFill; view.clipsToBounds = true; view.layer.cornerRadius = size / 2
            view.translatesAutoresizingMaskIntoConstraints = false
            badge.addSubview(view)
            NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: badge.leadingAnchor), view.trailingAnchor.constraint(equalTo: badge.trailingAnchor),
                                         view.topAnchor.constraint(equalTo: badge.topAnchor), view.bottomAnchor.constraint(equalTo: badge.bottomAnchor)])
            return badge
        }
        let label = UILabel()
        label.text = initials
        label.font = .systemFont(ofSize: size * 0.36, weight: .semibold)
        label.textColor = PorchStyle.accent
        center(label, in: badge)
        return badge
    }
    /// A symbol in the same circle, for a key with a control on it.
    static func symbolBadge(_ symbol: String, size: CGFloat = 44, empty: Bool = false) -> UIView {
        let badge = circle(size: size)
        if empty { badge.backgroundColor = nil; badge.layer.borderWidth = 1.5; badge.layer.borderColor = PorchStyle.border.cgColor }
        let icon = UIImageView(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: size * 0.38, weight: .semibold)))
        icon.tintColor = empty ? PorchStyle.secondary : PorchStyle.accent
        center(icon, in: badge)
        return badge
    }
    static func circle(size: CGFloat) -> UIView {
        let circle = UIView()
        circle.backgroundColor = PorchStyle.accent.withAlphaComponent(0.12)
        circle.layer.cornerRadius = size / 2
        circle.isAccessibilityElement = false
        NSLayoutConstraint.activate([circle.widthAnchor.constraint(equalToConstant: size), circle.heightAnchor.constraint(equalToConstant: size)])
        circle.setContentHuggingPriority(.required, for: .horizontal)
        return circle
    }
    static func center(_ view: UIView, in circle: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        circle.addSubview(view)
        NSLayoutConstraint.activate([view.centerXAnchor.constraint(equalTo: circle.centerXAnchor), view.centerYAnchor.constraint(equalTo: circle.centerYAnchor)])
    }
    /// A name over one or two lines about it, for list rows.
    static func text(_ title: String, _ details: [String?], titleColor: UIColor = PorchStyle.ink) -> UIStackView {
        let text = UIStackView(arrangedSubviews: [PorchStyle.label(title, size: 18, color: titleColor, weight: .medium)] + details.compactMap { $0 }.map { PorchStyle.label($0, size: 15) })
        text.axis = .vertical; text.spacing = 2
        return text
    }
}

extension FamilyPerson {
    var status: String { online ? "Porch is open on their device" : canReceiveCalls == true ? "Porch calls can ring while their device is locked" : "Their device is offline" }
    var shortStatus: String { online ? "Porch is open" : canReceiveCalls == true ? "Can ring while locked" : "Offline" }
    var dropInModes: String? {
        permissions.audio && permissions.video ? "Audio and video" : permissions.audio ? "Audio" : permissions.video ? "Video" : nil
    }
    /// Their ordinary calls drop in, as the drop-in types they're approved for.
    var callsDropIn: Bool { autoDropIn == true && dropInModes != nil }
    /// A one-line summary for the family list; nil when they can only make ordinary calls.
    var access: String? {
        let parts = [dropInModes.map { "\($0) drop-in" }, callsDropIn ? "Calls drop in" : nil, caregiver == true ? "Caregiver" : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
}

/// One page of caregiver settings. It's redrawn after every change, made here or by another caregiver.
class CaregiverPageViewController: CaregiverFormViewController {
    private(set) weak var admin: FamilyAdminViewController?
    let content = UIStackView()
    init(admin: FamilyAdminViewController) { self.admin = admin; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(admin:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        hideKeyboardControl()
        content.axis = .vertical; content.spacing = 28
        form.addArrangedSubview(content)
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .porchCaregiverChanged, object: admin)
        render()
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func changed() { render() }
    func render() {
        guard isViewLoaded else { return }
        content.arrangedSubviews.forEach { content.removeArrangedSubview($0); $0.removeFromSuperview() }
        guard let admin else { return }
        build(admin, admin.current)
    }
    /// Adds this page's settings to `content`.
    func build(_ admin: FamilyAdminViewController, _ state: FamilyAdminState?) {}
    /// A line under the page title that says what the page is about.
    func introduction(_ text: String) -> UILabel { PorchStyle.label(text, size: 17) }
    func push(_ controller: UIViewController) { navigationController?.pushViewController(controller, animated: true) }
}

/// The name family see for the bedside, such as Mom.
final class HouseholdNameViewController: CaregiverFormViewController {
    private weak var admin: FamilyAdminViewController?
    private let name = UITextField()
    init(admin: FamilyAdminViewController) { self.admin = admin; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(admin:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Name"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(save))
        name.text = admin?.current?.householdName
        name.accessibilityIdentifier = "caregiver.householdName"
        form.addArrangedSubview(field(name, title: "Who is this Porch for?", placeholder: "Your loved one"))
        // `field` resets capitalization. The name family see is capitalized word by word.
        name.autocapitalizationType = .words
    }
    @objc private func save() {
        view.endEditing(true)
        guard let admin else { return }
        navigationItem.rightBarButtonItem?.isEnabled = false
        Task {
            defer { self.navigationItem.rightBarButtonItem?.isEnabled = true }
            if await admin.perform("setHouseholdName", ["name": self.name.text ?? ""]) { self.finishSave() }
        }
    }
}

/// Who's on the keypad and who's in the family. On a family phone, just the family.
final class PeopleSettingsViewController: CaregiverPageViewController {
    override func viewDidLoad() { super.viewDidLoad(); title = admin?.onBedside == false ? "Family" : "People" }
    override func build(_ admin: FamilyAdminViewController, _ state: FamilyAdminState?) {
        if let slots = admin.slots {
            let keypad = UIStackView(arrangedSubviews: heading("Keypad") + [grid(slots, admin: admin)])
            keypad.axis = .vertical; keypad.spacing = 10
            content.addArrangedSubview(keypad)
        }
        content.addArrangedSubview(familyGroup(admin, state))
    }
    /// The keypad as it's laid out: 1 2 3, 4 5 6, 7 8 9, * 0 #.
    private func grid(_ slots: CallSlots, admin: FamilyAdminViewController) -> UIView {
        let order = [1, 2, 3, 4, 5, 6, 7, 8, 9, CallSlots.star, 0, CallSlots.pound]
        let grid = UIStackView(); grid.axis = .vertical; grid.spacing = 10
        for start in stride(from: 0, to: order.count, by: 3) {
            let row = UIStackView(arrangedSubviews: order[start..<start + 3].map { tile($0, slots: slots, admin: admin) })
            row.spacing = 10; row.distribution = .fillEqually; row.alignment = .fill
            grid.addArrangedSubview(row)
        }
        return grid
    }
    private func tile(_ digit: Int, slots: CallSlots, admin: FamilyAdminViewController) -> UIView {
        let key = CallSlots.symbol(for: digit)
        let action = slots.action(for: digit) ?? .unassigned
        let contact = slots.contact(for: digit)
        let title: String, detail: String?, badge: UIView
        switch action {
        case .person:
            title = contact?.name ?? ""
            badge = FamilyAdminViewController.avatar(contact?.name ?? key, photo: contact?.photoData)
            detail = contact.map { self.detail(for: $0, state: admin.current) }
        case .unassigned: title = "Add"; detail = nil; badge = FamilyAdminViewController.symbolBadge("plus", empty: true)
        case .callControl: title = "Answer / hang up"; detail = "Hold to decline"; badge = FamilyAdminViewController.symbolBadge("phone.fill")
        case .toggleVideo: title = "Video on / off"; detail = nil; badge = FamilyAdminViewController.symbolBadge("video.fill")
        case .messages: title = "Messages"; detail = nil; badge = FamilyAdminViewController.symbolBadge("envelope.fill")
        }
        let tile = KeypadTile(key: key, title: title, detail: detail, badge: badge, empty: action == .unassigned) { [weak self, weak admin] in
            guard let self, let admin else { return }
            if action == .person, contact != nil { self.push(PersonViewController(admin: admin, slot: digit)); return }
            let editor = SetupViewController(slot: digit, contact: nil, action: action)
            editor.onSaveSlot = { [weak admin] action, contact in
                try admin?.saveSlots { try $0.setContact(contact, for: digit); try $0.setAction(action, for: digit) }
            }
            self.push(editor)
        }
        tile.accessibilityIdentifier = "keypad.key.\(key)"
        tile.accessibilityLabel = "Key \(key), \(contact?.name ?? action.title)"
        tile.accessibilityValue = detail
        return tile
    }
    private func detail(for contact: CallContact, state: FamilyAdminState?) -> String {
        guard let call = contact.nativeCall else { return "Finish setup" }
        let mode = call.mode == .video ? "Video" : "Voice"
        if contact.familyMemberID != nil, state?.people.contains(where: { $0.id == contact.familyMemberID }) != false { return "Porch app · \(mode)" }
        if let invitation = contact.invitationID, state?.invitations?.contains(where: { $0.id == invitation }) == true { return "Invite sent" }
        return contact.phoneNumber == nil ? "Finish setup" : "Phone"
    }
    /// Everyone with access and everyone invited, so a pending invitation sits beside the people it will join.
    private func familyGroup(_ admin: FamilyAdminViewController, _ state: FamilyAdminState?) -> UIView {
        var rows: [UIView] = (state?.people ?? []).map { person in
            let name = person.id == admin.myID ? "\(person.name) (this phone)" : person.name
            let access = person.access ?? "Calls only"
            let photo = FamilyPhotos.shared.data(for: person.photoID)
            if photo == nil { admin.loadPhoto(of: person) }
            var views: [UIView] = [FamilyAdminViewController.avatar(person.name, photo: photo), FamilyAdminViewController.text(name, ["\(person.shortStatus) · \(access)"])]
            let key = admin.key(for: person).map { CallSlots.symbol(for: $0) }
            if let key { views.append(FamilyAdminViewController.singleLine(PorchStyle.label("Key \(key)", size: 15))) }
            let row = PorchListRow(views, label: "\(name). \(person.shortStatus). \(access)." + (key.map { " Key \($0)." } ?? "")) { [weak self, weak admin] in
                guard let self, let admin else { return }
                self.push(PersonViewController(admin: admin, memberID: person.id))
            }
            row.accessibilityIdentifier = "family.person.\(person.id)"
            return row
        }
        // Invitations last a day, so the expiry needs its day ("Tomorrow, 3:14 PM").
        let time = DateFormatter(); time.dateStyle = .short; time.timeStyle = .short; time.doesRelativeDateFormatting = true
        rows += (state?.invitations ?? []).map { invitation in
            let name = invitation.name ?? "Invitation"
            let clock = FamilyAdminViewController.symbolBadge("clock", empty: true)
            let text = FamilyAdminViewController.text(name, ["Invited · expires \(time.string(from: Date(timeIntervalSince1970: invitation.expiresAt)))"])
            let cancel = PorchStyle.button("Cancel", filled: false)
            cancel.configuration?.baseForegroundColor = .systemRed
            cancel.configuration?.contentInsets = .init(top: 10, leading: 12, bottom: 10, trailing: 4)
            cancel.accessibilityLabel = "Cancel invitation for \(name)"
            cancel.addAction(UIAction { [weak admin] _ in Task { await admin?.perform("cancelInvite", ["inviteID": invitation.id]) } }, for: .touchUpInside)
            let invited = UIStackView(arrangedSubviews: [clock, text]); invited.alignment = .center; invited.spacing = 12
            return listRow(invited, trailing: FamilyAdminViewController.singleLine(cancel))
        }
        rows.append(actionRow("Invite someone", symbol: "person.badge.plus") { [weak self, weak admin] in
            guard let self, let admin else { return }
            self.push(admin.inviteScreen())
        })
        return group(admin.slots == nil ? nil : "Family on Porch", rows: rows)
    }
}

/// One key on the People page's keypad: what it does, or who it calls.
final class KeypadTile: UIControl {
    init(key: String, title: String, detail: String?, badge: UIView, empty: Bool, action: @escaping () -> Void) {
        super.init(frame: .zero)
        backgroundColor = empty ? nil : PorchStyle.surface
        layer.cornerRadius = 16
        if empty { layer.borderWidth = 1.5; layer.borderColor = PorchStyle.border.cgColor }
        let number = PorchStyle.label(key, size: 17, color: PorchStyle.accent, weight: .bold)
        number.numberOfLines = 1
        let name = PorchStyle.label(title, size: 16, color: empty ? PorchStyle.secondary : PorchStyle.ink, weight: .medium)
        name.textAlignment = .center; name.numberOfLines = 2
        let views: [UIView] = [badge, name] + (detail.map { text -> [UIView] in
            let label = PorchStyle.label(text, size: 13); label.textAlignment = .center; label.numberOfLines = 2; return [label]
        } ?? [])
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical; stack.alignment = .center; stack.spacing = 6
        for view in [number, stack] { view.isUserInteractionEnabled = false; view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            number.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            number.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.topAnchor.constraint(equalTo: number.bottomAnchor, constant: 2),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
        addAction(UIAction { _ in action() }, for: .touchUpInside)
    }
    required init?(coder: NSCoder) { fatalError("Use init(key:title:detail:badge:empty:action:)") }
    override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.6 : 1 } }
}

/// Who can drop in, by Porch app and by phone, under the switch that pauses them all.
final class DropInSettingsViewController: CaregiverPageViewController {
    override func viewDidLoad() { super.viewDidLoad(); title = "Drop-in" }
    override func build(_ admin: FamilyAdminViewController, _ state: FamilyAdminState?) {
        content.addArrangedSubview(introduction("Drop-ins connect on their own after a short announcement."))
        let enabled = state?.dropInEnabled == true
        let master = UISwitch(); master.isOn = enabled
        master.accessibilityIdentifier = "dropIn.enabled"
        master.addAction(UIAction { [weak admin, weak master] _ in
            guard let admin, let master else { return }
            Task {
                if master.isOn && admin.onBedside {
                    guard await admin.requestMedia(video: state?.people.contains(where: { $0.permissions.video }) == true) else { master.isOn = false; return }
                }
                await admin.perform("setDropIn", ["enabled": master.isOn])
            }
        }, for: .valueChanged)
        var rows = [toggleRow("Allow drop-ins", detail: enabled ? nil : "Paused. Approvals are kept.", master)]
        // A drop-in answers on this iPad, so it needs the microphone and, for video, the camera.
        let video = state?.people.contains { $0.permissions.video } == true
        if admin.onBedside, enabled, AVCaptureDevice.authorizationStatus(for: .audio) == .denied || (video && AVCaptureDevice.authorizationStatus(for: .video) == .denied) {
            rows.append(listRow([PorchStyle.label("Allow the microphone\(video ? " and camera" : "") in Settings → Porch, or drop-ins can't connect.", size: 16, color: .systemRed)]))
        }
        content.addArrangedSubview(group(rows: rows))
        let ink = enabled ? PorchStyle.ink : PorchStyle.secondary
        let people = state?.people ?? []
        var can: [UIView] = people.filter { $0.permissions.audio || $0.permissions.video }.map { person in
            let modes = (person.dropInModes ?? "") + (person.callsDropIn ? " · Calls drop in" : "")
            return PorchListRow([FamilyAdminViewController.avatar(person.name, photo: FamilyPhotos.shared.data(for: person.photoID), size: 36),
                                 FamilyAdminViewController.text(person.name, [modes], titleColor: ink)],
                                label: "\(person.name), Porch app, \(modes)") { [weak self, weak admin] in
                guard let self, let admin else { return }
                self.push(PersonViewController(admin: admin, memberID: person.id))
            }
        }
        can += (state?.phoneDropIns ?? []).map { approval in
            let remove = PorchStyle.button("Remove", symbol: "minus.circle", filled: false)
            remove.configuration?.baseForegroundColor = .systemRed
            remove.configuration?.contentInsets = .init(top: 10, leading: 12, bottom: 10, trailing: 4)
            remove.accessibilityLabel = "Remove phone drop-in for \(approval.name)"
            remove.addAction(UIAction { [weak admin] _ in
                Task { await admin?.perform("setPhoneDropIn", ["number": approval.number, "enabled": false]) }
            }, for: .touchUpInside)
            let phone = FamilyAdminViewController.symbolBadge("phone.fill", size: 36)
            let text = UIStackView(arrangedSubviews: [phone, FamilyAdminViewController.text(approval.name, ["\(PhoneNumberNormalization.display(approval.number)) · By phone"], titleColor: ink)])
            text.alignment = .center; text.spacing = 12
            return listRow(text, trailing: FamilyAdminViewController.singleLine(remove))
        }
        if can.isEmpty { can.append(listRow([PorchStyle.label("No one yet.", size: 16)])) }
        can.append(actionRow("Add a phone number", symbol: "phone.badge.plus") { [weak self, weak admin] in
            guard let self, let admin else { return }
            self.push(admin.phoneDropInScreen())
        })
        content.addArrangedSubview(group("Can drop in", rows: can))
        let cannot = people.filter { !$0.permissions.audio && !$0.permissions.video }.map { person -> UIView in
            let off = FamilyAdminViewController.singleLine(PorchStyle.label("Off", size: 17))
            return PorchListRow([FamilyAdminViewController.avatar(person.name, photo: FamilyPhotos.shared.data(for: person.photoID), size: 36),
                                 FamilyAdminViewController.text(person.name, []), off],
                                label: "\(person.name), can't drop in") { [weak self, weak admin] in
                guard let self, let admin else { return }
                self.push(PersonViewController(admin: admin, memberID: person.id))
            }
        }
        if !cannot.isEmpty { content.addArrangedSubview(group("Can't drop in", rows: cannot)) }
    }
}

/// Family messages, the ones waiting to play, and on the bedside, playing them when someone sits down.
final class MessageSettingsViewController: CaregiverPageViewController {
    override func viewDidLoad() { super.viewDidLoad(); title = "Messages" }
    override func build(_ admin: FamilyAdminViewController, _ state: FamilyAdminState?) {
        let messagesOn = UISwitch(); messagesOn.isOn = state?.messagesEnabled != false
        messagesOn.accessibilityIdentifier = "messages.enabled"
        messagesOn.addAction(UIAction { [weak admin, weak messagesOn] _ in
            guard let admin, let messagesOn else { return }
            Task { await admin.perform("setMessages", ["enabled": messagesOn.isOn]) }
        }, for: .valueChanged)
        let waiting = state?.messages ?? []
        let held = waiting.filter { $0.held == true }.count
        let count = FamilyAdminViewController.singleLine(PorchStyle.label(waiting.isEmpty ? "None" : "\(waiting.count)", size: 18))
        let reviewText = UIStackView(arrangedSubviews: [PorchStyle.label("Waiting messages", size: 18, color: PorchStyle.ink)])
        reviewText.axis = .vertical; reviewText.spacing = 2
        // Phone voicemail from numbers that aren't on the keypad waits for a caregiver's OK.
        if held > 0 { reviewText.addArrangedSubview(PorchStyle.label("\(held) need\(held == 1 ? "s" : "") your OK", size: 15, color: PorchStyle.accent, weight: .semibold)) }
        let review = PorchListRow([reviewText, count],
                                  label: waiting.isEmpty ? "No messages waiting" : held > 0 ? "Waiting messages, \(waiting.count), \(held) need\(held == 1 ? "s" : "") your OK" : "Waiting messages, \(waiting.count)") { [weak self, weak admin] in
            guard let self, let admin else { return }
            let queue = MessageQueueViewController(remote: admin.remote, messages: waiting)
            queue.onChange = { [weak admin] state in admin?.adopt(state) }
            self.push(queue)
        }
        review.accessibilityIdentifier = "messages.review"
        review.isEnabled = !waiting.isEmpty
        content.addArrangedSubview(group(rows: [toggleRow("Allow family messages", messagesOn), review]))
        // Starting messages when someone sits down uses this iPad's camera, so it's set on the iPad itself.
        guard admin.onBedside else { return }
        let settings = MessageAutoplay.load()
        var autoplay = [autoplayToggle(settings.enabled)]
        if settings.enabled { autoplay += [hourRow("Starting at", \.startHour), hourRow("Until", \.endHour)] }
        content.addArrangedSubview(group(rows: autoplay))
    }
    private func autoplayToggle(_ enabled: Bool) -> UIView {
        let on = UISwitch(); on.isOn = enabled
        on.accessibilityIdentifier = "messages.autoplay"
        on.addAction(UIAction { [weak self, weak on] _ in
            guard let self, let on else { return }
            Task { @MainActor in
                if on.isOn, !(await AVCaptureDevice.requestAccess(for: .video)) {
                    on.setOn(false, animated: true)
                    self.admin?.showError(FamilyServiceError(message: "Allow camera access in iPad Settings → Porch to start messages when someone is in front of the iPad.", status: 403))
                    return
                }
                var settings = MessageAutoplay.load(); settings.enabled = on.isOn; settings.save()
                NotificationCenter.default.post(name: .porchMessageAutoplayChanged, object: nil)
                self.render()
            }
        }, for: .valueChanged)
        return toggleRow("Play when someone is in front of the iPad", detail: "Uses the camera. Nothing is recorded.", on)
    }
    private func hourRow(_ title: String, _ hour: WritableKeyPath<MessageAutoplay, Int>) -> UIView {
        let stepper = UIStepper()
        stepper.minimumValue = Double(MessageAutoplay.hourRange.lowerBound); stepper.maximumValue = Double(MessageAutoplay.hourRange.upperBound)
        stepper.value = Double(MessageAutoplay.load()[keyPath: hour])
        let value = PorchStyle.label(Self.hourText(Int(stepper.value)))
        let row = stepperRow(title, value: value, stepper)
        stepper.accessibilityLabel = "Play messages \(title.lowercased())"
        stepper.addAction(UIAction { [weak stepper, weak value] _ in
            guard let stepper else { return }
            var settings = MessageAutoplay.load(); settings[keyPath: hour] = Int(stepper.value); settings.save()
            value?.text = Self.hourText(Int(stepper.value)); stepper.accessibilityValue = value?.text
            NotificationCenter.default.post(name: .porchMessageAutoplayChanged, object: nil)
        }, for: .valueChanged)
        return row
    }
    static func hourText(_ hour: Int) -> String {
        let formatter = DateFormatter(); formatter.setLocalizedDateFormatFromTemplate("j")
        return formatter.string(from: Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date())
    }
}

/// What family learn about someone being at the iPad. Sharing it is a server setting, so a phone can change it too.
/// The camera check uses this iPad's own camera, so only the iPad shows that switch.
final class PrivacySettingsViewController: CaregiverPageViewController {
    override func viewDidLoad() { super.viewDidLoad(); title = "Privacy" }
    override func build(_ admin: FamilyAdminViewController, _ state: FamilyAdminState?) {
        let shared = state?.shareAttendance == true
        let share = UISwitch(); share.isOn = shared
        share.isEnabled = state?.shareAttendance != nil
        share.accessibilityIdentifier = "attendance.share"
        share.addAction(UIAction { [weak admin, weak share] _ in
            guard let admin, let share else { return }
            Task { await admin.perform("setShareAttendance", ["enabled": share.isOn]) }
        }, for: .valueChanged)
        let detail = state?.shareAttendance == nil ? "Not available on this Porch's server yet." : "Touches and key presses count."
        var rows = [toggleRow("Show family when someone is at the iPad", detail: detail, share)]
        if admin.onBedside { rows.append(cameraToggle(enabled: shared)) }
        content.addArrangedSubview(group(rows: rows))
        content.addArrangedSubview(textLink("Privacy policy", size: 15) { [weak self] in if let self { showPrivacyPolicy(on: self) } })
    }
    private func cameraToggle(enabled: Bool) -> UIView {
        let on = UISwitch(); on.isOn = BedsideAttendance.cameraEnabled()
        on.isEnabled = enabled
        on.accessibilityIdentifier = "attendance.camera"
        on.addAction(UIAction { [weak self, weak on] _ in
            guard let self, let on else { return }
            Task { @MainActor in
                if on.isOn, !(await AVCaptureDevice.requestAccess(for: .video)) {
                    on.setOn(false, animated: true)
                    self.admin?.showError(FamilyServiceError(message: "Allow camera access in iPad Settings → Porch to tell family when someone is at the iPad.", status: 403))
                    return
                }
                BedsideAttendance.setCameraEnabled(on.isOn)
                NotificationCenter.default.post(name: .porchAttendanceCameraChanged, object: nil)
            }
        }, for: .valueChanged)
        return toggleRow("Check with the camera", detail: "About every 30 seconds. Nothing is recorded.", on)
    }
}

/// Who can open caregiver mode from their phone, and on the bedside, its PIN.
final class CaregiverAccessViewController: CaregiverPageViewController {
    override func viewDidLoad() { super.viewDidLoad(); title = admin?.onBedside == false ? "Caregivers" : "Caregivers & PIN" }
    override func build(_ admin: FamilyAdminViewController, _ state: FamilyAdminState?) {
        content.addArrangedSubview(introduction("Caregivers can change settings from their phone with the PIN."))
        var rows: [UIView] = (state?.people ?? []).map { person in
            let isMe = person.id == admin.myID
            let caregiver = UISwitch(); caregiver.isOn = person.caregiver == true
            caregiver.isEnabled = !isMe
            caregiver.addAction(UIAction { [weak admin, weak caregiver] _ in
                guard let admin, let caregiver else { return }
                Task { await admin.perform("setCaregiver", ["memberID": person.id, "enabled": caregiver.isOn]) }
            }, for: .valueChanged)
            let row = toggleRow(isMe ? "\(person.name) (this phone)" : person.name, detail: isMe ? "Another caregiver can change this." : nil, caregiver)
            caregiver.accessibilityLabel = "\(person.name) is a caregiver"
            return row
        }
        if rows.isEmpty { rows.append(listRow([PorchStyle.label("No family members yet.", size: 16)])) }
        content.addArrangedSubview(group(rows: rows))
        guard admin.onBedside else { return }
        content.addArrangedSubview(group(rows: [linkRow("Change caregiver PIN", symbol: "lock.rotation") { [weak self] in
            self?.push(ChangeCaregiverPINViewController())
        }]))
    }
}
