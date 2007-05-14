class AmiLogicGenerator < Rails::Generator::Base
  def manifest
    record do |m|
      m.directory File.join('app/ami_logic')
      m.template "ami_logic.rb", File.join('app/ami_logic', "ami_logic.rb")
    end
  end
end
