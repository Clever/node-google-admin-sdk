require('coffee-script/register');

module.exports = {
  AdminSDK: require("./lib/google_api_admin_sdk"),
  GroupProvisioning: require("./lib/group_provisioning"),
  UserProvisioning: require("./lib/user_provisioning"),
  OrgUnitProvisioning: require("./lib/org_unit_provisioning"),
  Batch: require("./lib/batch"),
  GoogleQuery: require("./lib/query")
};
