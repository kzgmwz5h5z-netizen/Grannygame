import SwiftUI
import SceneKit
import AVFoundation

@main
struct GrannyHorrorGameApp: App {
    var body: some Scene {
        WindowGroup {
            MainGameView()
                .ignoresSafeArea()
                .statusBar(hidden: true)
        }
    }
}

// MARK: - حالة اللعبة والأدوات
enum GameItem: String, CaseIterable {
    case none = "يد فارغة"
    case hammer = "مطرقة 🔨"
    case wireCutter = "قطاعة أسلاك 钳"
    case safeKey = "مفتاح الخزنة 🗝️"
    case masterKey = "المفتاح الرئيسي 🔑"
}

class GameManager: ObservableObject {
    @Published var currentDay: Int = 1
    @Published var heldItem: GameItem = .none
    @Published var isHiding: Bool = false
    @Published var statusMessage: String = "اليوم 1: ابحث عن طريقة للهروب بدون أن تراك العجوز!"
    @Published var isGameOver: Bool = false
    @Published var isGameWon: Bool = false
    @Published var showDayTransition: Bool = true
    @Published var showJumpscare: Bool = false
    
    // حالة أقفال باب الهروب والأماكن السرية
    @Published var woodPlankRemoved: Bool = false
    @Published var wiresCut: Bool = false
    @Published var secretPassageOpened: Bool = false
    @Published var safeOpened: Bool = false
    
    // مراجع المشهد ثلاثي الأبعاد
    var scene = SCNScene()
    var cameraNode = SCNNode()
    var playerNode = SCNNode()
    var grannyNode = SCNNode()
    var secretWallNode: SCNNode?
    var plankNode: SCNNode?
    var wireBoxNode: SCNNode?
    var safeDoorNode: SCNNode?
    
    // متغيرات الحركة
    var moveJoystick: CGPoint = .zero
    var cameraYaw: Float = 0.0
    var cameraPitch: Float = 0.0
    private var gameTimer: Timer?
    private var grannyWaypoints: [SCNVector3] = [
        SCNVector3(0, 1, -8),
        SCNVector3(8, 1, -8),
        SCNVector3(8, 1, 5),
        SCNVector3(-6, 1, 5),
        SCNVector3(-6, 1, -5)
    ]
    private var currentWaypointIndex = 0
    
    init() {
        setupScene()
        startGameLoop()
        startDayBanner()
    }
    
    func startDayBanner() {
        showDayTransition = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                self.showDayTransition = false
            }
        }
    }
    
    // MARK: - بناء العالم ثلاثي الأبعاد (البيت والألغاز)
    func setupScene() {
        scene = SCNScene()
        scene.background.contents = UIColor.black
        scene.fogStartDistance = 2.0
        scene.fogEndDistance = 16.0
        scene.fogColor = UIColor.black
        
        // إعداد اللاعب والكاميرا والكشاف
        playerNode = SCNNode()
        playerNode.position = SCNVector3(-6, 1.6, -6) // غرفة البداية
        
        cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 75
        cameraNode.camera?.zNear = 0.1
        
        // كشاف يدوي (Flashlight)
        let flashlight = SCNLight()
        flashlight.type = .spot
        flashlight.color = UIColor(white: 1.0, alpha: 1.0)
        flashlight.intensity = 1200
        flashlight.spotInnerAngle = 20
        flashlight.spotOuterAngle = 55
        flashlight.attenuationStartDistance = 1.0
        flashlight.attenuationEndDistance = 18.0
        cameraNode.light = flashlight
        
        // إضاءة محيطية خافتة جداً
        let ambientNode = SCNNode()
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 40
        ambientLight.color = UIColor.darkGray
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)
        
        playerNode.addChildNode(cameraNode)
        scene.rootNode.addChildNode(playerNode)
        
        buildHouse()
        spawnItemsAndPuzzles()
        spawnGranny()
    }
    
    func buildHouse() {
        // الأرضية والسقف
        let floor = SCNBox(width: 24, height: 0.2, length: 24, chamferRadius: 0)
        floor.firstMaterial?.diffuse.contents = UIColor(red: 0.15, green: 0.1, blue: 0.08, alpha: 1)
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(0, -0.1, 0)
        scene.rootNode.addChildNode(floorNode)
        
        let ceilingNode = floorNode.clone()
        ceilingNode.position = SCNVector3(0, 3.6, 0)
        scene.rootNode.addChildNode(ceilingNode)
        
        // الجدران الخارجية
        createWall(w: 24, h: 3.6, l: 0.5, x: 0, z: -12) // شمال
        createWall(w: 24, h: 3.6, l: 0.5, x: 0, z: 12)  // جنوب
        createWall(w: 0.5, h: 3.6, l: 24, x: -12, z: 0) // غرب
        createWall(w: 0.5, h: 3.6, l: 24, x: 12, z: 0)  // شرق
        
        // تقسيم الغرف الداخلية
        createWall(w: 8, h: 3.6, l: 0.4, x: -8, z: -2) // جدار غرفة البداية
        createWall(w: 0.4, h: 3.6, l: 6, x: -2, z: -9) // ممر
        createWall(w: 10, h: 3.6, l: 0.4, x: 7, z: 0)  // جدار الغرفة الشرقية
        
        // الجدار السري (يفتح عند ضغط الزر المخفي خلف اللوحة)
        let secretWallGeo = SCNBox(width: 4.0, height: 3.6, length: 0.4, chamferRadius: 0)
        secretWallGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.25, green: 0.22, blue: 0.2, alpha: 1)
        let sWall = SCNNode(geometry: secretWallGeo)
        sWall.position = SCNVector3(-8, 1.8, 4)
        sWall.name = "secret_wall"
        scene.rootNode.addChildNode(sWall)
        self.secretWallNode = sWall
        
        // سرير الاختباء في غرفة البداية
        let bed = SCNBox(width: 2.2, height: 0.6, length: 3.0, chamferRadius: 0.1)
        bed.firstMaterial?.diffuse.contents = UIColor(red: 0.4, green: 0.1, blue: 0.1, alpha: 1)
        let bedNode = SCNNode(geometry: bed)
        bedNode.position = SCNVector3(-9.5, 0.3, -9.5)
        bedNode.name = "interact_bed"
        scene.rootNode.addChildNode(bedNode)
    }
    
    func createWall(w: CGFloat, h: CGFloat, l: CGFloat, x: Float, z: Float) {
        let wall = SCNBox(width: w, height: h, length: l, chamferRadius: 0)
        wall.firstMaterial?.diffuse.contents = UIColor(red: 0.28, green: 0.26, blue: 0.22, alpha: 1)
        let node = SCNNode(geometry: wall)
        node.position = SCNVector3(x, Float(h/2), z)
        node.name = "wall"
        scene.rootNode.addChildNode(node)
    }
    
    func spawnItemsAndPuzzles() {
        // 1. الباب الرئيسي للهروب (في الجدار الجنوبي)
        let exitDoor = SCNBox(width: 2.2, height: 3.0, length: 0.6, chamferRadius: 0)
        exitDoor.firstMaterial?.diffuse.contents = UIColor.brown
        let exitNode = SCNNode(geometry: exitDoor)
        exitNode.position = SCNVector3(0, 1.5, 11.7)
        exitNode.name = "interact_exitDoor"
        scene.rootNode.addChildNode(exitNode)
        
        // الخشبة اللي تسد الباب الرئيسي
        let plank = SCNBox(width: 2.6, height: 0.3, length: 0.7, chamferRadius: 0)
        plank.firstMaterial?.diffuse.contents = UIColor.orange
        let pNode = SCNNode(geometry: plank)
        pNode.position = SCNVector3(0, 1.5, 11.5)
        pNode.name = "interact_exitDoor"
        scene.rootNode.addChildNode(pNode)
        self.plankNode = pNode
        
        // صندوق الأسلاك الكهربائية بجانب الباب
        let wireBox = SCNBox(width: 0.6, height: 0.8, length: 0.4, chamferRadius: 0)
        wireBox.firstMaterial?.diffuse.contents = UIColor.red
        let wNode = SCNNode(geometry: wireBox)
        wNode.position = SCNVector3(2.0, 1.6, 11.6)
        wNode.name = "interact_wireBox"
        scene.rootNode.addChildNode(wNode)
        self.wireBoxNode = wNode
        
        // 2. اللوحة السرية (تفتح الممر السري)
        let painting = SCNBox(width: 1.5, height: 1.5, length: 0.1, chamferRadius: 0)
        painting.firstMaterial?.diffuse.contents = UIColor.purple
        let paintNode = SCNNode(geometry: painting)
        paintNode.position = SCNVector3(0, 1.8, -11.6)
        paintNode.name = "interact_painting"
        scene.rootNode.addChildNode(paintNode)
        
        // 3. الخزنة داخل الغرفة السرية (خلف الجدار السري)
        let safe = SCNBox(width: 1.2, height: 1.2, length: 1.2, chamferRadius: 0.05)
        safe.firstMaterial?.diffuse.contents = UIColor.darkGray
        let sNode = SCNNode(geometry: safe)
        sNode.position = SCNVector3(-9, 0.6, 9)
        sNode.name = "interact_safe"
        scene.rootNode.addChildNode(sNode)
        self.safeDoorNode = sNode
        
        // 4. توزيع الأدوات في الغرف
        // المطرقة (في الغرفة الشرقية)
        createItemNode(name: "item_hammer", color: .cyan, pos: SCNVector3(9, 0.4, -8))
        // قطاعة الأسلاك (في الصالة الجنوبية الشرقية)
        createItemNode(name: "item_wireCutter", color: .yellow, pos: SCNVector3(9, 0.4, 8))
        // مفتاح الخزنة (في الممر الشمالي)
        createItemNode(name: "item_safeKey", color: .green, pos: SCNVector3(4, 0.4, -10))
    }
    
    func createItemNode(name: String, color: UIColor, pos: SCNVector3) {
        let geo = SCNBox(width: 0.5, height: 0.5, length: 0.5, chamferRadius: 0.1)
        geo.firstMaterial?.diffuse.contents = color
        geo.firstMaterial?.emission.contents = color.withAlphaComponent(0.4) // توهج خفيف عشان تشوفه بالظلام
        let node = SCNNode(geometry: geo)
        node.position = pos
        node.name = name
        scene.rootNode.addChildNode(node)
    }
    
    func spawnGranny() {
        grannyNode = SCNNode()
        grannyNode.position = SCNVector3(8, 0, 5)
        
        // جسم الوحش
        let body = SCNCylinder(radius: 0.45, height: 1.7)
        body.firstMaterial?.diffuse.contents = UIColor(red: 0.3, green: 0.05, blue: 0.05, alpha: 1)
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 0.85, 0)
        grannyNode.addChildNode(bodyNode)
        
        // الرأس والعيون المضيئة المرعبة
        let head = SCNSphere(radius: 0.35)
        head.firstMaterial?.diffuse.contents = UIColor.lightGray
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 1.9, 0)
        
        let eyeGeo = SCNSphere(radius: 0.06)
        eyeGeo.firstMaterial?.diffuse.contents = UIColor.red
        eyeGeo.firstMaterial?.emission.contents = UIColor.red
        let leftEye = SCNNode(geometry: eyeGeo)
        leftEye.position = SCNVector3(-0.12, 0.05, -0.3)
        let rightEye = SCNNode(geometry: eyeGeo)
        rightEye.position = SCNVector3(0.12, 0.05, -0.3)
        headNode.addChildNode(leftEye)
        headNode.addChildNode(rightEye)
        
        grannyNode.addChildNode(headNode)
        scene.rootNode.addChildNode(grannyNode)
    }
    
    // MARK: - حلقة التحديث المستمرة (حركة اللاعب + ذكاء الوحش)
    func startGameLoop() {
        gameTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            self?.updateGame()
        }
    }
    
    func updateGame() {
        guard !isGameOver && !isGameWon && !showDayTransition && !showJumpscare else { return }
        
        // 1. تحديث حركة اللاعب إذا ما كان مختبئ
        if !isHiding {
            let speed: Float = 0.14
            let dx = Float(moveJoystick.x) * speed
            let dz = Float(moveJoystick.y) * speed
            
            let forwardX = -sin(cameraYaw)
            let forwardZ = -cos(cameraYaw)
            let rightX = cos(cameraYaw)
            let rightZ = -sin(cameraYaw)
            
            let moveX = (forwardX * (-dz)) + (rightX * dx)
            let moveZ = (forwardZ * (-dz)) + (rightZ * dx)
            
            let newX = max(-11.2, min(11.2, playerNode.position.x + moveX))
            let newZ = max(-11.2, min(11.2, playerNode.position.z + moveZ))
            
            playerNode.position = SCNVector3(newX, 1.6, newZ)
        }
        
        // تحديث زاوية نظر الكاميرا
        playerNode.eulerAngles.y = cameraYaw
        cameraNode.eulerAngles.x = cameraPitch
        
        // 2. تحديث حركة الوحش (Granny AI)
        updateGrannyAI()
    }
    
    func updateGrannyAI() {
        let pPos = playerNode.position
        let gPos = grannyNode.position
        let distToPlayer = hypot(pPos.x - gPos.x, pPos.z - gPos.z)
        
        var targetPos: SCNVector3
        var moveSpeed: Float = 0.065 // سرعة التجول العادية
        
        // إذا اللاعب مو مختبئ وقريب من الوحش، يطارده!
        if !isHiding && distToPlayer < 9.5 {
            targetPos = SCNVector3(pPos.x, 0, pPos.z)
            moveSpeed = 0.11 // سرعة المطاردة
        } else {
            // التجول بين النقاط (Patrol)
            targetPos = grannyWaypoints[currentWaypointIndex]
            let distToWP = hypot(targetPos.x - gPos.x, targetPos.z - gPos.z)
            if distToWP < 1.0 {
                currentWaypointIndex = (currentWaypointIndex + 1) % grannyWaypoints.count
            }
        }
        
        // تحريك الوحش باتجاه الهدف
        let angle = atan2(targetPos.x - gPos.x, targetPos.z - gPos.z)
        grannyNode.eulerAngles.y = angle + .pi
        grannyNode.position.x += sin(angle) * moveSpeed
        grannyNode.position.z += cos(angle) * moveSpeed
        
        // فحص إذا مسك اللاعب
        if !isHiding && distToPlayer < 1.3 {
            triggerCaughtByGranny()
        }
    }
    
    func triggerCaughtByGranny() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        showJumpscare = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.showJumpscare = false
            if self.currentDay < 5 {
                self.currentDay += 1
                self.playerNode.position = SCNVector3(-6, 1.6, -6)
                self.grannyNode.position = SCNVector3(8, 0, 5)
                self.statusMessage = "اليوم \(self.currentDay): انتبه! الصوت والحركة يجذبونها."
                self.startDayBanner()
            } else {
                self.isGameOver = true
            }
        }
    }
    
    // MARK: - التفاعل مع الأشياء والألغاز
    func interact() {
        if isHiding {
            isHiding = false
            playerNode.position.y = 1.6
            statusMessage = "خرجت من مخبأك."
            return
        }
        
        // البحث عن أقرب عنصر قابل للتفاعل أمام اللاعب
        let pPos = playerNode.position
        var closestNode: SCNNode?
        var minDist: Float = 3.2 // مدى اليد
        
        for child in scene.rootNode.childNodes {
            guard let name = child.name, (name.starts(with: "item_") || name.starts(with: "interact_")) else { continue }
            let d = hypot(child.position.x - pPos.x, child.position.z - pPos.z)
            if d < minDist {
                minDist = d
                closestNode = child
            }
        }
        
        guard let target = closestNode, let name = target.name else {
            statusMessage = "لا يوجد شيء قريب للتفاعل معه."
            return
        }
        
        switch name {
        case "interact_bed":
            isHiding = true
            playerNode.position = SCNVector3(target.position.x, 0.35, target.position.z)
            statusMessage = "أنت مختبئ تحت السرير الآن! اضغط 'تفاعل' للخروج."
            
        case "item_hammer":
            pickupItem(.hammer, node: target)
        case "item_wireCutter":
            pickupItem(.wireCutter, node: target)
        case "item_safeKey":
            pickupItem(.safeKey, node: target)
        case "item_masterKey":
            pickupItem(.masterKey, node: target)
            
        case "interact_painting":
            if !secretPassageOpened {
                secretPassageOpened = true
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 1.5
                secretWallNode?.position.y = -3.0 // ينزل الجدار السري للأرض
                SCNTransaction.commit()
                statusMessage = "سمعت صوت جدار يتحرك! لقد فتحت الممر السري للقبو!"
            } else {
                statusMessage = "الممر السري مفتوح بالفعل."
            }
            
        case "interact_safe":
            if heldItem == .safeKey && !safeOpened {
                safeOpened = true
                heldItem = .none
                createItemNode(name: "item_masterKey", color: .red, pos: SCNVector3(-9, 1.4, 9))
                statusMessage = "فتحت الخزنة السرية! ظهر لك المفتاح الرئيسي الأحمر!"
            } else if !safeOpened {
                statusMessage = "خزنة حديدية مقفلة.. تحتاج إلى (مفتاح الخزنة 🗝️)."
            } else {
                statusMessage = "الخزنة مفتوحة."
            }
            
        case "interact_wireBox":
            if heldItem == .wireCutter && !wiresCut {
                wiresCut = true
                wireBoxNode?.geometry?.firstMaterial?.diffuse.contents = UIColor.green
                statusMessage = "قطعت أسلاك الإنذار والكهرباء عن الباب الرئيسي!"
            } else if !wiresCut {
                statusMessage = "صندوق كهرباء الباب! تحتاج إلى (قطاعة أسلاك) لفصله."
            } else {
                statusMessage = "الكهرباء مفصولة بالفعل."
            }
            
        case "interact_exitDoor":
            if !woodPlankRemoved {
                if heldItem == .hammer {
                    woodPlankRemoved = true
                    plankNode?.removeFromParentNode()
                    statusMessage = "كسرت الخشب بالمطرقة! باقي تفصل الكهرباء وتجيب المفتاح الرئيسي."
                } else {
                    statusMessage = "الباب مسدود بخشب عريض! تحتاج إلى (مطرقة 🔨) لكسره."
                }
            } else if !wiresCut {
                statusMessage = "القفل الإلكتروني شغال! افصل صندوق الأسلاك اللي جنب الباب أولاً."
            } else if heldItem == .masterKey {
                isGameWon = true
            } else {
                statusMessage = "تحتاج إلى (المفتاح الرئيسي 🔑) عشان تفتح القفل الأخير وتهرب!"
            }
            
        default:
            break
        }
    }
    
    func pickupItem(_ newItem: GameItem, node: SCNNode) {
        // إذا كان شايل غرض من قبل، يرميه على الأرض في مكانه الحالي
        if heldItem != .none {
            dropCurrentItem()
        }
        heldItem = newItem
        node.removeFromParentNode()
        statusMessage = "التقطت: \(newItem.rawValue)"
    }
    
    func dropCurrentItem() {
        guard heldItem != .none else { return }
        let pPos = playerNode.position
        let dropPos = SCNVector3(pPos.x, 0.4, pPos.z)
        
        switch heldItem {
        case .hammer:
            createItemNode(name: "item_hammer", color: .cyan, pos: dropPos)
        case .wireCutter:
            createItemNode(name: "item_wireCutter", color: .yellow, pos: dropPos)
        case .safeKey:
            createItemNode(name: "item_safeKey", color: .green, pos: dropPos)
        case .masterKey:
            createItemNode(name: "item_masterKey", color: .red, pos: dropPos)
        case .none:
            break
        }
        statusMessage = "رميت \(heldItem.rawValue) على الأرض (انتبه العجوز تسمع الصوت!)."
        heldItem = .none
    }
    
    func restartGame() {
        currentDay = 1
        heldItem = .none
        isHiding = false
        woodPlankRemoved = false
        wiresCut = false
        secretPassageOpened = false
        safeOpened = false
        isGameOver = false
        isGameWon = false
        setupScene()
        startDayBanner()
    }
}

// MARK: - واجهة المستخدم والتحكم (SwiftUI)
struct MainGameView: View {
    @StateObject private var game = GameManager()
    @State private var dragStartAngle: CGPoint = .zero
    
    var body: some View {
        ZStack {
            // 1. عرض المشهد ثلاثي الأبعاد
            SceneView(scene: game.scene, pointOfView: game.cameraNode)
                .ignoresSafeArea()
            
            // 2. منطقة تحريك الكاميرا (النصف الأيمن من الشاشة)
            HStack(spacing: 0) {
                Color.clear.frame(width: 220) // مخصص للجويستيك
                Color.white.opacity(0.001)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let sensitivity: Float = 0.006
                                game.cameraYaw -= Float(value.translation.width) * sensitivity * 0.15
                                let newPitch = game.cameraPitch - Float(value.translation.height) * sensitivity * 0.15
                                game.cameraPitch = max(-0.8, min(0.8, newPitch))
                            }
                    )
            }
            
            // 3. نقطة التصويب في وسط الشاشة (Crosshair)
            Circle()
                .fill(Color.white.opacity(0.7))
                .frame(width: 8, height: 8)
            
            // 4. واجهة المعلومات والأزرار (HUD)
            VStack {
                // الشريط العلوي
                HStack {
                    Text("اليوم \(game.currentDay) / 5")
                        .font(.title2.bold())
                        .foregroundColor(.red)
                        .padding(10)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                    
                    Spacer()
                    
                    Text(game.statusMessage)
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                    
                    Spacer()
                    
                    Text("في يدك: \(game.heldItem.rawValue)")
                        .font(.subheadline.bold())
                        .foregroundColor(.yellow)
                        .padding(10)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                }
                .padding(.horizontal, 25)
                .padding(.top, 20)
                
                Spacer()
                
                // أزرار التحكم السفلية
                HStack(alignment: .bottom) {
                    // عصا التحكم بالمشي (Joystick)
                    JoystickView(joystickPos: $game.moveJoystick)
                        .padding(.leading, 40)
                        .padding(.bottom, 30)
                    
                    Spacer()
                    
                    // أزرار التفاعل ورمي الغرض
                    HStack(spacing: 20) {
                        if game.heldItem != .none {
                            Button(action: { game.dropCurrentItem() }) {
                                Text("رمي الغرض ⬇️")
                                    .font(.headline.bold())
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.gray.opacity(0.8))
                                    .cornerRadius(15)
                            }
                        }
                        
                        Button(action: { game.interact() }) {
                            Text(game.isHiding ? "خروج 🛏️" : "تفاعل ✋")
                                .font(.title3.bold())
                                .foregroundColor(.black)
                                .frame(width: 130, height: 65)
                                .background(Color.yellow)
                                .cornerRadius(20)
                                .shadow(radius: 5)
                        }
                    }
                    .padding(.trailing, 40)
                    .padding(.bottom, 30)
                }
            }
            
            // 5. شاشة الفجعة (Jumpscare)
            if game.showJumpscare {
                ZStack {
                    Color.red.opacity(0.85).ignoresSafeArea()
                    VStack {
                        Text("👁️   👁️")
                            .font(.system(size: 110))
                        Text("مسكتك العجوز!")
                            .font(.largeTitle.bold())
                            .foregroundColor(.white)
                    }
                }
            }
            
            // 6. شاشة الانتقال بين الأيام
            if game.showDayTransition {
                ZStack {
                    Color.black.ignoresSafeArea()
                    Text("DAY \(game.currentDay)")
                        .font(.system(size: 70, weight: .heavy, design: .serif))
                        .foregroundColor(.red)
                }
            }
            
            // 7. شاشة الفوز أو الخسارة
            if game.isGameOver || game.isGameWon {
                ZStack {
                    Color.black.opacity(0.95).ignoresSafeArea()
                    VStack(spacing: 25) {
                        Text(game.isGameWon ? "🎉 نجحت في الهروب من البيت!" : "💀 انتهت الأيام الخمسة.. لقد خسرت!")
                            .font(.largeTitle.bold())
                            .foregroundColor(game.isGameWon ? .green : .red)
                        
                        Button(action: { game.restartGame() }) {
                            Text("العب مرة ثانية 🔄")
                                .font(.title2.bold())
                                .foregroundColor(.black)
                                .padding(.horizontal, 35)
                                .padding(.vertical, 15)
                                .background(Color.white)
                                .cornerRadius(15)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - تصميم الجويستيك (Joystick)
struct JoystickView: View {
    @Binding var joystickPos: CGPoint
    @State private var thumbOffset: CGSize = .zero
    let maxRadius: CGFloat = 55
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.5), lineWidth: 4)
                .background(Circle().fill(Color.black.opacity(0.4)))
                .frame(width: maxRadius * 2, height: maxRadius * 2)
            
            Circle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 50, height: 50)
                .offset(thumbOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let dx = value.translation.width
                            let dy = value.translation.height
                            let distance = hypot(dx, dy)
                            if distance <= maxRadius {
                                thumbOffset = value.translation
                            } else {
                                let angle = atan2(dy, dx)
                                thumbOffset = CGSize(width: cos(angle) * maxRadius, height: sin(angle) * maxRadius)
                            }
                            joystickPos = CGPoint(x: thumbOffset.width / maxRadius, y: thumbOffset.height / maxRadius)
                        }
                        .onEnded { _ in
                            withAnimation(.spring()) {
                                thumbOffset = .zero
                                joystickPos = .zero
                            }
                        }
                )
        }
    }
}
