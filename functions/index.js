const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

exports.notifyAdminOnDamageReport = functions.firestore
  .document('damage_reports/{reportId}')
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const umbrellaId = data.umbrellaId;
    const damageType = data.type || "Unknown Issue";
    const reporterName = data.reporterName || "A user";

    const payload = {
      notification: {
        title: 'New Damage Report',
        body: `${reporterName} reported ${damageType} for Umbrella #${umbrellaId}.`,
      },
      data: {
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
        reportId: context.params.reportId,
        umbrellaId: umbrellaId,
        type: 'damage_report'
      }
    };

    try {
      const response = await admin.messaging().sendToTopic('admin_alerts', payload);
      console.log('Successfully sent message:', response);
      return null;
    } catch (error) {
      console.error('Error sending message:', error);
      throw new Error("Failed to send notification");
    }
  });
