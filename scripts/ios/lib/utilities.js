const fs = require('fs');
const Utilities = {};

Utilities.getPreferenceValueFromConfig = function (config, name) {
  const value = config.match(new RegExp('name="' + name + '" value="(.*?)"', "i"))
  if (value && value[1]) {
    return value[1]
  } else {
    return null
  }
}

Utilities.getPreferenceValueFromPackageJson = function (packageJson, name) {
  const value = packageJson.match(new RegExp('"' + name + '":\\s"(.*?)"', "i"));
  if (value && value[1]) {
    return value[1]
  } else {
    return null
  }
}

Utilities.getPreferenceValue = function (name) {
  const config = fs.readFileSync("config.xml").toString();
  let preferenceValue = Utilities.getPreferenceValueFromConfig(config, name);
  if (!preferenceValue) {
    const packageJson = fs.readFileSync("package.json").toString();
    preferenceValue = Utilities.getPreferenceValueFromPackageJson(packageJson, name)
  }
  return preferenceValue
}

Utilities.getPlistPath = function (context) {
  const common = context.requireCordovaModule('cordova-common');
  const util = context.requireCordovaModule('cordova-lib/src/cordova/util');
  const projectName = new common.ConfigParser(util.projectConfig(util.isCordova())).name();
  // cordova-ios 8.0.0 renamed the project directory from the app name to 'App'
  const dirName = fs.existsSync('./platforms/ios/' + projectName) ? projectName : 'App';
  return './platforms/ios/' + dirName + '/' + dirName + '-Info.plist'
}

module.exports = Utilities;
