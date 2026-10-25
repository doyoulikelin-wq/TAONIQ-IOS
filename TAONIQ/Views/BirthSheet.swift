import SwiftUI

struct BirthSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var birthDate: Date
    @State private var gender: String
    let onGenerate: (BirthInput) -> Void
    private let earliest = TaoTheme.parse("1901-01-01T00:00:00")!

    init(input: BirthInput, onGenerate: @escaping (BirthInput) -> Void) {
        _birthDate = State(initialValue: TaoTheme.parse(input.birth) ?? Date())
        _gender = State(initialValue: input.gender)
        self.onGenerate = onGenerate
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    VStack(alignment: .leading, spacing: 14) {
                        TaijiMark(size: 34)
                        Text("落下时间的原点")
                            .font(.system(size: 27, weight: .regular, design: .serif))
                        Text("输入公历生辰，生成你的生辰核与流盘。")
                            .font(.subheadline).foregroundStyle(TaoTheme.muted)
                    }
                    VStack(spacing: 0) {
                        DatePicker("出生日期", selection: $birthDate, in: earliest...Date(), displayedComponents: .date)
                            .accessibilityIdentifier("birthDate")
                            .padding(.vertical, 18)
                        Divider().overlay(TaoTheme.line)
                        DatePicker("出生时间", selection: $birthDate, in: earliest...Date(), displayedComponents: .hourAndMinute)
                            .accessibilityIdentifier("birthTime")
                            .padding(.vertical, 18)
                    }
                    .datePickerStyle(.compact)
                    .font(.subheadline)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("排运设定").font(.subheadline)
                        Picker("排运设定", selection: $gender) {
                            Text("男").tag("male")
                            Text("女").tag("female")
                        }.pickerStyle(.segmented)
                            .accessibilityIdentifier("genderPicker")
                        Text("用于传统大运顺逆计算。采用北京时间 UTC+08，不校正真太阳时。")
                            .font(.caption).foregroundStyle(TaoTheme.muted).lineSpacing(4)
                    }
                    Button {
                        let value = BirthInput(birth: TaoTheme.format(birthDate, pattern: "yyyy-MM-dd'T'HH:mm:ss"), gender: gender)
                        onGenerate(value)
                        dismiss()
                    } label: {
                        HStack {
                            Text("生成轨迹")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .padding(.horizontal, 22).frame(height: 56)
                        .foregroundStyle(TaoTheme.paper)
                        .background(TaoTheme.ink, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("generateButton")
                    Text("生辰仅保存在此设备，轨迹在本机计算。")
                        .font(.caption2).foregroundStyle(TaoTheme.muted)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 26).padding(.top, 20).padding(.bottom, 30)
                .frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .background(TaoTheme.paper)
            .navigationTitle("生辰")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }.foregroundStyle(TaoTheme.ink)
                }
            }
        }
        .tint(TaoTheme.ink)
        .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
        .environment(\.calendar, TaoTheme.calendar)
        .environment(\.timeZone, TaoTheme.timeZone)
    }
}
