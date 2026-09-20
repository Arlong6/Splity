#!/usr/bin/env ruby
# frozen_string_literal: true
#
# 讀寫 Splity target 的版號。
#
# 為什麼不用 sed：project.pbxproj 裡 MARKETING_VERSION 與 CURRENT_PROJECT_VERSION
# 各出現 6 次——app target 的 Debug/Release 兩份，以及測試 target 們的 1.0 / 2。
# `sed -i '' "s/MARKETING_VERSION = .*;/.../g"` 會把六處全部改掉，測試 target 的
# 1.0 會被寫成 1.8.2。而且對 pbxproj 做文字替換本身就是高風險操作。
#
# 用法：
#   scripts/version.rb read              # 印出「<marketing> <build>」一行
#   scripts/version.rb set 1.8.3 19      # 只改 Splity target 的兩個設定
#
# 需求：xcodeproj gem（gem install xcodeproj）。

require "xcodeproj"

TARGET_NAME = "Splity"
PROJECT_PATH = File.expand_path("../Splity.xcodeproj", __dir__)

def splity_target(project)
  project.targets.find { |t| t.name == TARGET_NAME } ||
    abort("找不到 target #{TARGET_NAME}")
end

# 同一個 target 的各 configuration 應該版號一致；不一致代表有人手動改壞了，
# 這時寧可停下來讓人看一眼，也不要默默挑一個回傳。
def single_value(configs, key)
  values = configs.map { |c| c.build_settings[key] }.compact.map(&:to_s).uniq
  abort("#{TARGET_NAME} 的 #{key} 在各 configuration 不一致：#{values.join(', ')}") if values.size > 1
  abort("#{TARGET_NAME} 沒有設定 #{key}") if values.empty?
  values.first
end

command = ARGV.shift

case command
when "read"
  project = Xcodeproj::Project.open(PROJECT_PATH)
  configs = splity_target(project).build_configurations
  puts "#{single_value(configs, 'MARKETING_VERSION')} #{single_value(configs, 'CURRENT_PROJECT_VERSION')}"

when "set"
  marketing, build = ARGV
  abort("用法：scripts/version.rb set <marketing> <build>") if marketing.nil? || build.nil?
  abort("版號格式不對：#{marketing}（預期像 1.8.3）") unless marketing.match?(/\A\d+(\.\d+){1,2}\z/)
  abort("Build 號要是整數：#{build}") unless build.match?(/\A\d+\z/)

  project = Xcodeproj::Project.open(PROJECT_PATH)
  changed = []
  splity_target(project).build_configurations.each do |config|
    settings = config.build_settings
    if settings["MARKETING_VERSION"] != marketing
      changed << "#{config.name} MARKETING_VERSION #{settings['MARKETING_VERSION']} -> #{marketing}"
      settings["MARKETING_VERSION"] = marketing
    end
    if settings["CURRENT_PROJECT_VERSION"].to_s != build
      changed << "#{config.name} CURRENT_PROJECT_VERSION #{settings['CURRENT_PROJECT_VERSION']} -> #{build}"
      settings["CURRENT_PROJECT_VERSION"] = build
    end
  end
  project.save
  changed.each { |line| puts "  #{line}" }
  puts "  （沒有變更）" if changed.empty?

else
  abort("用法：scripts/version.rb read | scripts/version.rb set <marketing> <build>")
end
