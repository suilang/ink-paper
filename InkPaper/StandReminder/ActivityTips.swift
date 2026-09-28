import Foundation

/// 活动提醒的指导动作文案库。
/// 每次触发按 `cycleIndex` 轮转抽取，覆盖手指/脚踝/肩颈/眼部/腰背等部位。
/// 文案只描述动作本身，不含具体时长或次数——时长由倒计时统一呈现，避免与大休息不匹配。
struct ActivityTip: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let detail: String
}

enum ActivityTips {
    /// 文案库。覆盖手脚、肩颈、眼部、腰背、呼吸，以及起身走动、喝水等日常放松动作。
    static let all: [ActivityTip] = [
        .init(title: "活动手指", detail: "双手用力张开再握拳，反复做直至手指发热"),
        .init(title: "活动脚踝", detail: "抬起脚，顺时针、逆时针转动脚踝，放松小腿"),
        .init(title: "放松肩颈", detail: "双肩向上耸近耳根，保持片刻再缓缓放下"),
        .init(title: "远眺休息", detail: "望向窗外远处，让眼睛从屏幕距离上移开"),
        .init(title: "伸展腰背", detail: "坐直，双手上举向天花板方向拉伸，配合深呼吸"),
        .init(title: "活动颈椎", detail: "下巴缓慢画「米」字，每个方向都停顿一下"),
        .init(title: "活动手腕", detail: "手腕向前向后屈伸，缓解长时间握鼠标的僵硬"),
        .init(title: "转动眼球", detail: "眼球顺时针、逆时针各转几圈，再轻轻眨眼"),
        .init(title: "深呼吸", detail: "缓慢吸气、屏息、再缓缓呼出，让呼吸变深变长"),
        .init(title: "站立伸展", detail: "站起来，双手向上够向天花板，把身体拉长"),
        .init(title: "活动髋部", detail: "坐姿，双膝左右轻摆，放松骨盆与下腰"),
        .init(title: "搓手热敷", detail: "双手快速搓热，轻敷在闭着的眼睑上"),
        .init(title: "起身走走", detail: "站起来离开座位，在屋里随便溜达几步"),
        .init(title: "去接杯水吧", detail: "走到茶水间接杯水，顺便让眼睛歇会儿"),
        .init(title: "抬抬腿", detail: "坐在椅子上把一条腿水平抬起，换另一条腿再来"),
        .init(title: "扩扩胸", detail: "双手在背后相握，挺胸夹紧肩胛骨，打开胸腔"),
        .init(title: "转转腰", detail: "双手叉腰，上身缓慢左右转动，放松腰部"),
        .init(title: "抖抖手脚", detail: "自然垂下双手，抖动手腕和脚踝，甩掉紧绷感"),
        .init(title: "按按穴位", detail: "用拇指揉按合谷、风池穴，缓解头面疲劳"),
        .init(title: "闭目养神", detail: "闭上眼，什么都不看，让大脑放空一会儿"),
    ]

    /// 按 `cycleIndex` 轮转取一条（保证不短期重复）。
    static func pick(cycleIndex: Int) -> ActivityTip {
        let count = all.count
        let idx = (cycleIndex % count + count) % count
        return all[idx]
    }
}
