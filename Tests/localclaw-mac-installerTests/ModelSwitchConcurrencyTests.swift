import Foundation
import Testing
@testable import localclaw_mac_installer

@MainActor
struct ModelSwitchConcurrencyTests {
    @Test(arguments: ["chat", "model", "installer"])
    func updatesCannotInterruptActiveWork(_ operation: String) {
        let vm = InstallerViewModel()
        vm.chatIsSending = operation == "chat"
        vm.modeSwitchInProgress = operation == "model"
        vm.isRunning = operation == "installer"
        vm.installerUpdateStatus = "Update available"
        vm.recoveryStatus = "Existing recovery status"
        vm.updateLocalClawFromDMG()
        vm.updateAll()
        vm.updateOpenClawRuntime()
        vm.updateDependenciesOnly()
        #expect(vm.installerUpdateStatus == "Update available")
        #expect(vm.recoveryStatus == "Existing recovery status")
        #expect(vm.isRunning == (operation == "installer"))
    }

    @Test func restoringCloudSelectionAlsoRestoresItsProviderAndAuthenticationMode() {
        let vm = InstallerViewModel()
        vm.inferenceMode = .oauth
        vm.selectedCloudAuthMode = .oauth
        vm.selectedProvider = .openAI
        vm.selectedChatModel = "openrouter/fixture/model"
        vm.syncChatModelModeWithSelection()
        #expect(vm.inferenceMode == .cloud)
        #expect(vm.selectedCloudAuthMode == .api)
        #expect(vm.selectedProvider == .openRouter)
        #expect(vm.selectedOpenRouterModel == "openrouter/fixture/model")
    }

    @Test func restoringLocalSelectionClearsThePreviousOAuthMode() {
        let vm = InstallerViewModel()
        vm.inferenceMode = .oauth
        vm.selectedCloudAuthMode = .oauth
        vm.selectedProvider = .openAI
        vm.selectedChatModel = "lmstudio/fixture/model"
        vm.syncChatModelModeWithSelection()
        #expect(vm.inferenceMode == .local)
        #expect(vm.selectedChatResponseMode == .local)
        #expect(vm.selectedCloudAuthMode == .api)
        #expect(vm.selectedProvider == .custom)
    }

    @Test func switchingModelKeepsUnsentChatDraftAndSession() {
        let vm = InstallerViewModel()
        vm.modeSwitchInProgress = true
        vm.chatInput = "Keep this draft until the Gateway is ready"
        vm.chatImagePath = "/tmp/fixture-image.png"
        let session = vm.activeChatSessionID
        vm.sendChatMessage()
        #expect(vm.chatInput == "Keep this draft until the Gateway is ready")
        #expect(vm.chatImagePath == "/tmp/fixture-image.png")
        #expect(vm.activeChatSessionID == session)
        #expect(!vm.chatIsSending)
    }

    @Test func activeChatPreventsModelSwitchBeforeAnyWork() {
        let vm = InstallerViewModel()
        vm.chatIsSending = true
        vm.modeSwitchStatus = "Existing status"
        vm.applyInferenceModeSwitch()
        #expect(!vm.modeSwitchInProgress)
        #expect(vm.modeSwitchStatus == "Existing status")
    }

    @Test func installerWorkPreventsModelSwitchBeforeAnyWork() {
        let vm = InstallerViewModel()
        vm.isRunning = true
        vm.modeSwitchStatus = "Installing"
        vm.applyInferenceModeSwitch()
        #expect(!vm.modeSwitchInProgress)
        #expect(vm.modeSwitchStatus == "Installing")
    }
}
