require 'xcodeproj'

project_path = 'Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Check if target already exists
if project.targets.any? { |t| t.name == 'RunnerUITests' }
  puts 'RunnerUITests target already exists'
  exit 0
end

# Get Runner target for reference
runner = project.targets.find { |t| t.name == 'Runner' }
unless runner
  puts 'Runner target not found!'
  exit 1
end

# Create UI Testing Bundle target
target = project.new_target(:ui_testing_bundle, 'RunnerUITests', :ios, '13.0')
target.build_configurations.each do |config|
  config.build_settings['INFOPLIST_FILE'] = 'RunnerUITests/Info.plist'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'kr.pins.RunnerUITests'
  config.build_settings['TEST_TARGET_NAME'] = 'Runner'
  config.build_settings['CLANG_ENABLE_MODULES'] = 'YES'
end

# Add source file group
group = project.main_group.find_subpath('RunnerUITests', true)
group.set_source_tree('<group>')
group.set_path('RunnerUITests')

source_file = group.new_file('RunnerUITests.m')
source_file.set_source_tree('<group>')
source_file.set_path('RunnerUITests.m')

plist_file = group.new_file('Info.plist')
plist_file.set_source_tree('<group>')
plist_file.set_path('Info.plist')

# Add source file to target
target.add_file_references([source_file])

project.save

puts 'RunnerUITests target added successfully'
puts "Targets: #{project.targets.map(&:name).join(', ')}"
