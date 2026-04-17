require 'xcodeproj'
require 'fileutils'

root = File.expand_path('..', __dir__)
project_path = File.join(root, 'ytbackground.xcodeproj')
project = Xcodeproj::Project.new(project_path)
user = ENV.fetch('USER', 'user')
youtube_player_kit_sources = Dir.glob(File.join(root, '.tmp-youtubeplayerkit', 'Sources', '**', '*.swift')).sort.map { |path| path.delete_prefix(root + '/') }

def add_files(project, target, files, build_phase)
  files.each do |relative_path|
    file_ref = project.files.find { |ref| ref.path == relative_path } || project.new_file(relative_path)
    build_phase.add_file_reference(file_ref, true)
  end
end

app_target = project.new_target(:application, 'ytbackground', :ios, '17.0')
widget_target = project.new_target(:app_extension, 'ytbackgroundActivity', :ios, '17.0')
share_target = project.new_target(:app_extension, 'ytbackgroundShare', :ios, '17.0')

app_target.add_dependency(widget_target)
app_target.add_dependency(share_target)

embed_phase = app_target.new_copy_files_build_phase('Embed App Extensions')
embed_phase.symbol_dst_subfolder_spec = :plug_ins

[app_target, widget_target, share_target].each do |target|
  target.build_configurations.each do |config|
    xcconfig = File.join(root, 'Config', "#{config.name}.xcconfig")
    config.base_configuration_reference = project.new_file(xcconfig)
    config.build_settings['SWIFT_VERSION'] = '5.0'
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
    config.build_settings['DEVELOPMENT_TEAM'] = '$(DEVELOPMENT_TEAM)'
    config.build_settings['CODE_SIGN_ENTITLEMENTS'] = case target.name
      when 'ytbackground' then 'App/ytbackground.entitlements'
      when 'ytbackgroundActivity' then 'Widget/ytbackgroundWidget.entitlements'
      else 'ShareExtension/ytbackgroundShare.entitlements'
    end
  end
end

app_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = '$(PRODUCT_BUNDLE_IDENTIFIER_PREFIX).ytbackground'
  config.build_settings['INFOPLIST_FILE'] = 'App/Info.plist'
  config.build_settings['PRODUCT_NAME'] = 'ytbackground'
  config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  config.build_settings['INFOPLIST_KEY_APP_GROUP_IDENTIFIER'] = '$(APP_GROUP_IDENTIFIER)'
  config.build_settings['INFOPLIST_KEY_YOUTUBE_DATA_API_KEY'] = '$(YOUTUBE_DATA_API_KEY)'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks']
end

widget_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = '$(PRODUCT_BUNDLE_IDENTIFIER_PREFIX).ytbackground.activity'
  config.build_settings['INFOPLIST_FILE'] = 'Widget/Info.plist'
  config.build_settings['PRODUCT_NAME'] = 'ytbackgroundActivity'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
end

share_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = '$(PRODUCT_BUNDLE_IDENTIFIER_PREFIX).ytbackground.share'
  config.build_settings['INFOPLIST_FILE'] = 'ShareExtension/Info.plist'
  config.build_settings['PRODUCT_NAME'] = 'ytbackgroundShare'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
end

frameworks = {
  'WebKit.framework' => 'System/Library/Frameworks/WebKit.framework',
  'WidgetKit.framework' => 'System/Library/Frameworks/WidgetKit.framework',
  'UIKit.framework' => 'System/Library/Frameworks/UIKit.framework',
  'UniformTypeIdentifiers.framework' => 'System/Library/Frameworks/UniformTypeIdentifiers.framework'
}

framework_refs = frameworks.transform_values { |path| project.frameworks_group.new_file(path) }

app_target.frameworks_build_phase.add_file_reference(framework_refs['WebKit.framework'])
widget_target.frameworks_build_phase.add_file_reference(framework_refs['WidgetKit.framework'])
share_target.frameworks_build_phase.add_file_reference(framework_refs['UIKit.framework'])
share_target.frameworks_build_phase.add_file_reference(framework_refs['UniformTypeIdentifiers.framework'])

sources = {
  app_target => %w[
    App/AppDelegate.swift
    App/ytbackgroundApp.swift
    App/RootView.swift
    App/Shared/AppGroup.swift
    App/Shared/Models.swift
    App/Shared/PlaybackActivityAttributes.swift
    App/Shared/PlaylistPickerSheet.swift
    App/Shared/SharedStore.swift
    App/Persistence/PlaylistModels.swift
    App/Services/Configuration.swift
    App/Services/YouTubeURLParser.swift
    App/Services/YouTubeAPIClient.swift
    App/Services/PlaybackService.swift
    App/Persistence/PlaylistRepository.swift
    App/Features/Search/SearchViewModel.swift
    App/Features/Search/SearchView.swift
    App/Features/Player/PlayerView.swift
    App/Features/Player/YouTubeWebPlayerView.swift
    App/Features/Playlists/PlaylistsView.swift
  ] + youtube_player_kit_sources,
  widget_target => %w[
    App/Shared/AppGroup.swift
    App/Shared/Models.swift
    App/Shared/SharedStore.swift
    App/Shared/PlaybackActivityAttributes.swift
    Widget/ytbackgroundWidget.swift
  ],
  share_target => %w[
    App/Shared/AppGroup.swift
    App/Shared/Models.swift
    App/Shared/SharedStore.swift
    ShareExtension/ShareViewController.swift
  ]
}

sources.each do |target, files|
  add_files(project, target, files, target.source_build_phase)
end

resources = {
  app_target => ['App/Assets.xcassets', 'App/LaunchScreen.storyboard'],
  widget_target => [],
  share_target => []
}

resources.each do |target, files|
  add_files(project, target, files, target.resources_build_phase)
end

[widget_target, share_target].each do |target|
  embed_phase.add_file_reference(target.product_reference, true)
end

project.save

scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app_target, nil)
scheme.launch_action.build_configuration = 'Debug'
scheme.test_action.build_configuration = 'Debug'
scheme.profile_action.build_configuration = 'Release'
scheme.analyze_action.build_configuration = 'Debug'
scheme.archive_action.build_configuration = 'Release'

scheme.launch_action.buildable_product_runnable = Xcodeproj::XCScheme::BuildableProductRunnable.new(app_target)

shared_schemes_dir = File.join(project_path, 'xcshareddata', 'xcschemes')
FileUtils.mkdir_p(shared_schemes_dir)
scheme.save_as(project_path, 'ytbackground', true)

scheme_path = File.join(shared_schemes_dir, 'ytbackground.xcscheme')
scheme_contents = File.read(scheme_path)
launch_macro = <<~XML
      <MacroExpansion>
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "#{app_target.uuid}"
            BuildableName = "ytbackground.app"
            BlueprintName = "ytbackground"
            ReferencedContainer = "container:ytbackground.xcodeproj">
         </BuildableReference>
      </MacroExpansion>
XML

unless scheme_contents.include?('<MacroExpansion>')
  scheme_contents.sub!('   </LaunchAction>', launch_macro + "   </LaunchAction>")
  File.write(scheme_path, scheme_contents)
end

user_scheme_dir = File.join(project_path, 'xcuserdata', "#{user}.xcuserdatad", 'xcschemes')
FileUtils.mkdir_p(user_scheme_dir)
scheme_management = <<~PLIST
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>SchemeUserState</key>
      <dict>
        <key>ytbackground.xcscheme_^#shared#^_</key>
        <dict>
          <key>isShown</key>
          <true/>
          <key>orderHint</key>
          <integer>0</integer>
        </dict>
      </dict>
      <key>SuppressBuildableAutocreation</key>
      <dict>
        <key>#{app_target.uuid}</key>
        <dict>
          <key>primary</key>
          <true/>
        </dict>
        <key>#{widget_target.uuid}</key>
        <dict>
          <key>primary</key>
          <false/>
        </dict>
        <key>#{share_target.uuid}</key>
        <dict>
          <key>primary</key>
          <false/>
        </dict>
      </dict>
    </dict>
    </plist>
PLIST

File.write(File.join(user_scheme_dir, 'xcschememanagement.plist'), scheme_management)
