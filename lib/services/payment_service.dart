import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class PaymentService {
  late Razorpay _razorpay;
  final Function(PaymentSuccessResponse)? onSuccess;
  final Function(PaymentFailureResponse)? onFailure;
  final Function(ExternalWalletResponse)? onExternalWallet;

  PaymentService({this.onSuccess, this.onFailure, this.onExternalWallet}) {
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    if (onSuccess != null) onSuccess!(response);
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    if (onFailure != null) onFailure!(response);
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    if (onExternalWallet != null) onExternalWallet!(response);
  }

  void openCheckout({
    required double amount,
    required String contact,
    required String email,
    required String description,
    String? apiKey,
  }) {
    final key =
        apiKey ?? dotenv.env['RAZORPAY_KEY'] ?? 'rzp_test_YOUR_KEY_HERE';

    // Validate key format (basic check)
    if (key.startsWith('rzp_test_YOUR')) {
      debugPrint('WARNING: Razorpay key not properly configured in .env');
    }

    var options = {
      'key': key,
      'amount': (amount * 100).toInt(), // Amount in paise
      'name': 'RainNest Umbrella',
      'description': description,
      'currency': 'INR',
      'retry': {'enabled': true, 'max_count': 4},
      'theme': {'color': '#0066FF'},
      'timeout': 60, // in seconds
      'prefill': {
        'contact': contact.isNotEmpty ? contact : '9999999999',
        'email': email.isNotEmpty ? email : 'user@rainnest.com',
      },
      'external': {
        'wallets': ['paytm'],
      },
      'send_sms_hash': true,
    };

    debugPrint('Opening Razorpay Checkout for amount: $amount');
    debugPrint('Payment Details: $description');

    try {
      _razorpay.open(options);
    } catch (e) {
      debugPrint('Error opening Razorpay: $e');
    }
  }

  void dispose() {
    _razorpay.clear();
  }
}
