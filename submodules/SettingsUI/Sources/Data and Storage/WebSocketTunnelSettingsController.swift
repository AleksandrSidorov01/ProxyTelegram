import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

private final class WebSocketTunnelSettingsControllerArguments {
    let updateMode: (WSTunnelMode) -> Void

    init(updateMode: @escaping (WSTunnelMode) -> Void) {
        self.updateMode = updateMode
    }
}

private enum WebSocketTunnelSettingsSection: Int32 {
    case mode
    case status
}

private enum WebSocketTunnelSettingsEntry: ItemListNodeEntry {
    case modeHeader(PresentationTheme, String)
    case modeAuto(PresentationTheme, String, Bool)
    case modeAlways(PresentationTheme, String, Bool)
    case modeDisabled(PresentationTheme, String, Bool)
    case modeInfo(PresentationTheme, String)
    case statusHeader(PresentationTheme, String)
    case statusIndicator(PresentationTheme, String, WSTunnelConnectionStatus)
    case statusInfo(PresentationTheme, String)

    var section: ItemListSectionId {
        switch self {
        case .modeHeader, .modeAuto, .modeAlways, .modeDisabled, .modeInfo:
            return WebSocketTunnelSettingsSection.mode.rawValue
        case .statusHeader, .statusIndicator, .statusInfo:
            return WebSocketTunnelSettingsSection.status.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .modeHeader:
            return 0
        case .modeAuto:
            return 1
        case .modeAlways:
            return 2
        case .modeDisabled:
            return 3
        case .modeInfo:
            return 4
        case .statusHeader:
            return 5
        case .statusIndicator:
            return 6
        case .statusInfo:
            return 7
        }
    }

    static func ==(lhs: WebSocketTunnelSettingsEntry, rhs: WebSocketTunnelSettingsEntry) -> Bool {
        switch lhs {
        case let .modeHeader(lhsTheme, lhsText):
            if case let .modeHeader(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                return true
            } else {
                return false
            }
        case let .modeAuto(lhsTheme, lhsText, lhsValue):
            if case let .modeAuto(rhsTheme, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                return true
            } else {
                return false
            }
        case let .modeAlways(lhsTheme, lhsText, lhsValue):
            if case let .modeAlways(rhsTheme, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                return true
            } else {
                return false
            }
        case let .modeDisabled(lhsTheme, lhsText, lhsValue):
            if case let .modeDisabled(rhsTheme, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                return true
            } else {
                return false
            }
        case let .modeInfo(lhsTheme, lhsText):
            if case let .modeInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                return true
            } else {
                return false
            }
        case let .statusHeader(lhsTheme, lhsText):
            if case let .statusHeader(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                return true
            } else {
                return false
            }
        case let .statusIndicator(lhsTheme, lhsText, lhsStatus):
            if case let .statusIndicator(rhsTheme, rhsText, rhsStatus) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsStatus == rhsStatus {
                return true
            } else {
                return false
            }
        case let .statusInfo(lhsTheme, lhsText):
            if case let .statusInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                return true
            } else {
                return false
            }
        }
    }

    static func <(lhs: WebSocketTunnelSettingsEntry, rhs: WebSocketTunnelSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! WebSocketTunnelSettingsControllerArguments
        switch self {
        case let .modeHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .modeAuto(_, text, value):
            return ItemListCheckboxItem(presentationData: presentationData, title: text, style: .left, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.updateMode(.auto)
            })
        case let .modeAlways(_, text, value):
            return ItemListCheckboxItem(presentationData: presentationData, title: text, style: .left, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.updateMode(.always)
            })
        case let .modeDisabled(_, text, value):
            return ItemListCheckboxItem(presentationData: presentationData, title: text, style: .left, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.updateMode(.disabled)
            })
        case let .modeInfo(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .statusHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .statusIndicator(_, text, status):
            let statusText: String
            switch status {
            case .direct:
                statusText = "Прямое подключение"
            case .tunnel(let dcId):
                statusText = "Туннель (DC\(dcId))"
            case .disconnected:
                statusText = "Отключено"
            }
            return ItemListDisclosureItem(presentationData: presentationData, title: text, label: statusText, sectionId: self.section, style: .blocks, action: nil)
        case let .statusInfo(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func webSocketTunnelSettingsControllerEntries(presentationData: PresentationData) -> [WebSocketTunnelSettingsEntry] {
    var entries: [WebSocketTunnelSettingsEntry] = []

    let currentMode = WebSocketTunnelManager.shared.tunnelMode
    let currentStatus = WebSocketTunnelManager.shared.connectionStatus

    entries.append(.modeHeader(presentationData.theme, "РЕЖИМ РАБОТЫ"))
    entries.append(.modeAuto(presentationData.theme, "Авто", currentMode == .auto))
    entries.append(.modeAlways(presentationData.theme, "Всегда", currentMode == .always))
    entries.append(.modeDisabled(presentationData.theme, "Выключено", currentMode == .disabled))

    let modeInfoText: String
    switch currentMode {
    case .auto:
        modeInfoText = "Автоматически использует WebSocket туннель при обнаружении блокировки Telegram."
    case .always:
        modeInfoText = "Всегда использует WebSocket туннель для всех подключений."
    case .disabled:
        modeInfoText = "WebSocket туннель отключён. Используется только прямое TCP подключение."
    }
    entries.append(.modeInfo(presentationData.theme, modeInfoText))

    entries.append(.statusHeader(presentationData.theme, "СТАТУС ПОДКЛЮЧЕНИЯ"))
    entries.append(.statusIndicator(presentationData.theme, "Текущее состояние", currentStatus))
    entries.append(.statusInfo(presentationData.theme, "Статус показывает текущий тип подключения к серверам Telegram."))

    return entries
}

public func webSocketTunnelSettingsController(context: AccountContext) -> ViewController {
    let statePromise = ValuePromise(0, ignoreRepeated: true)

    let arguments = WebSocketTunnelSettingsControllerArguments(
        updateMode: { mode in
            WebSocketTunnelManager.shared.tunnelMode = mode
            statePromise.set(statePromise.get() + 1)
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries = webSocketTunnelSettingsControllerEntries(presentationData: presentationData)

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Антиблокировка"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks
        )

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    return controller
}
