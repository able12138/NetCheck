import SwiftUI

@main
struct NetCheckApp: App {
    @StateObject private var app = AppModel()
    @StateObject private var speed = NetSpeedMonitor()
    @AppStorage("showMenuBarSpeed") private var showMenuBarSpeed = true

    var body: some Scene {
        WindowGroup("网络体检") {
            ContentView(app: app)
                .frame(minWidth: 900, minHeight: 620)
                .task { speed.start(ifName: NetSpeedMonitor.defaultInterface()) }
        }
        .defaultSize(width: 1100, height: 730)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        // 菜单栏实时网速（对位电脑管家的加速球）
        MenuBarExtra {
            MenuPanel(app: app, speed: speed)
        } label: {
            MenuBarLabel(speed: speed)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    @AppStorage("defaultSeconds") private var seconds = 12.0
    @AppStorage("defaultConnections") private var connections = 8
    @AppStorage("showMenuBarSpeed") private var showMenuBarSpeed = true

    var body: some View {
        Form {
            Section("测速参数") {
                HStack {
                    Text("下载测试时长")
                    Slider(value: $seconds, in: 5 ... 30, step: 1)
                    Text("\(Int(seconds)) 秒").monospacedDigit().frame(width: 60)
                }
                Stepper("并发连接数：\(connections)", value: $connections, in: 2 ... 16)
            }
            Section("界面") {
                Text("菜单栏显示的 ↓ / ↑ 为实时收发速率，每秒采样一次默认网卡（无需测速即可看到真实流量）。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("说明") {
                Text("并发连接数越高越能跑满宽带，但也会给对端节点更大压力。默认 8 连接 / 12 秒，适合国内千兆以内宽带。")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 330)
    }
}
