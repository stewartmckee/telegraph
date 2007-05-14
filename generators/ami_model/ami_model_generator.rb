class AmiModelGenerator < Rails::Generator::NamedBase
  def manifest
    record do |m|
      m.directory File.join('app/models')
      m.template "model.rb", File.join('app/models', "#{file_name}.rb")
    end
  end
end