import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:country_code_picker/country_code_picker.dart';
import '../../data/models/user_model.dart';
import '../../services/database_service.dart';
import '../widgets/rain_nest_loader.dart';
import 'home_page.dart';

class LoginDetailsPage extends StatefulWidget {
  const LoginDetailsPage({super.key});

  @override
  State<LoginDetailsPage> createState() => _LoginDetailsPageState();
}

class _LoginDetailsPageState extends State<LoginDetailsPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();

  final DatabaseService _db = DatabaseService();
  String _selectedCountryCode = '+91';
  bool _isLoading = false;
  bool _isFormValid = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.displayName != null) {
      _nameController.text = user.displayName!;
    }
    _nameController.addListener(_validateForm);
    _phoneController.addListener(_validateForm);
    _addressController.addListener(_validateForm);
    _pinController.addListener(_validateForm);
  }

  void _validateForm() {
    // This will trigger validation for all fields and update their error texts.
    // We then check if the form is currently valid.
    final isValid = _formKey.currentState?.validate() ?? false;
    if (isValid != _isFormValid) {
      setState(() {
        _isFormValid = isValid;
      });
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_validateForm);
    _phoneController.removeListener(_validateForm);
    _addressController.removeListener(_validateForm);
    _pinController.removeListener(_validateForm);
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _submitDetails() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final fullPhoneNumber =
              "$_selectedCountryCode${_phoneController.text.trim()}";
          UserModel userModel = UserModel(
            uid: user.uid,
            phoneNumber: fullPhoneNumber,
            name: _nameController.text.trim(),
            address: _addressController.text.trim(),
            pinCode: _pinController.text.trim(),
            email: user.email ?? '',
            createdAt: DateTime.now(),
          );
          await _db.saveUser(userModel);
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const HomePage()),
          );
        }
      } catch (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 600),
        tween: Tween(begin: 0.0, end: 1.0),
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 20 * (1 - value)),
              child: child,
            ),
          );
        },
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Top Gradient Header with Logo
              Container(
                height: MediaQuery.of(context).size.height * 0.4,
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF00ADEE), Color(0xFF0066FF)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(50),
                    bottomRight: Radius.circular(50),
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/images/logo.png',
                        height: 320,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                              Icons.cloud,
                              size: 300,
                              color: Colors.white,
                            ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),

              // Form Content as a Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Transform.translate(
                  offset: const Offset(0, -40),
                  child: Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 25,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      onChanged: _validateForm,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Center(
                            child: Column(
                              children: [
                                Text(
                                  "Complete Your Profile",
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1F2937),
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  "Please provide your details below",
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),

                          _buildFieldLabel("Name"),
                          TextFormField(
                            controller: _nameController,
                            textInputAction: TextInputAction.next,
                            decoration: _buildInputDecoration(
                              "Enter your full name",
                            ),
                            validator: (v) => (v == null || v.isEmpty)
                                ? "Name is required"
                                : null,
                          ),
                          const SizedBox(height: 20),

                          _buildFieldLabel("Phone Number"),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                height: 52,
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey[200]!),
                                ),
                                child: CountryCodePicker(
                                  onChanged: (code) {
                                    setState(() {
                                      _selectedCountryCode =
                                          code.dialCode ?? '+91';
                                    });
                                  },
                                  initialSelection: 'IN',
                                  favorite: const ['+91', 'IN'],
                                  showCountryOnly: false,
                                  showOnlyCountryWhenClosed: false,
                                  alignLeft: false,
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                  decoration: _buildInputDecoration(
                                    "Phone number",
                                  ),
                                  validator: (v) => (v == null || v.isEmpty)
                                      ? "Required"
                                      : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          _buildFieldLabel("Address"),
                          TextFormField(
                            controller: _addressController,
                            maxLines: 3,
                            textInputAction: TextInputAction.next,
                            decoration: _buildInputDecoration(
                              "Enter full address",
                            ),
                            validator: (v) => (v == null || v.isEmpty)
                                ? "Address is required"
                                : null,
                          ),
                          const SizedBox(height: 20),

                          _buildFieldLabel("Pin Code"),
                          TextFormField(
                            controller: _pinController,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submitDetails(),
                            decoration: _buildInputDecoration(
                              "6-digit pin code",
                            ),
                            maxLength: 6,
                            validator: (v) {
                              if (v == null || v.isEmpty) return "Required";
                              if (v.length != 6) return "Must be 6 digits";
                              if (int.tryParse(v) == null) {
                                return "Numbers only";
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 32),

                          // Submit Button
                          SizedBox(
                            width: double.infinity,
                            height: 55,
                            child: ElevatedButton(
                              onPressed: (_isLoading || !_isFormValid)
                                  ? null
                                  : _submitDetails,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0066FF),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: const Color(
                                  0xFF0066FF,
                                ).withValues(alpha: 0.5),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: _isLoading
                                  ? const RainNestLoader(
                                      size: 24,
                                      color: Colors.white,
                                    )
                                  : const Text(
                                      "Submit Details",
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF4B5563),
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[200]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[200]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF0066FF), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1),
      ),
    );
  }
}
