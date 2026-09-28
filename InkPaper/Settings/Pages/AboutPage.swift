import AppKit
import SwiftUI

struct AboutPage: View {
    var body: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

        return ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)

                    Text("Ink Paper")
                        .font(.title.bold())

                    Text("macOS 静态壁纸工具")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("版本 \(version)（\(build)）· 支持 macOS 13+")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                Form {
                    Section {
                        LabeledContent("开源协议", value: "MIT License")
                        LabeledContent("项目主页") {
                            Link("github.com/suilang/ink-paper", destination: URL(string: "https://github.com/suilang/ink-paper")!)
                        }
                    } header: {
                        Text("信息")
                    }

                    Section {
                        VStack(spacing: 12) {
                            Text("如果本项目对您有帮助，欢迎请作者喝杯奶茶。")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)

                            Image("WeChatPay")
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .frame(width: 200, height: 196)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
                                .accessibilityLabel("微信赞赏码")

                            Text("微信扫码赞赏 · 仅用于本项目维护与开发")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                    } header: {
                        Text("赞助")
                    }
                }
                .formStyle(.grouped)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 16)
        }
    }
}
