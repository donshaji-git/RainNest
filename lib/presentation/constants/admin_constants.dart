class AdminConstants {
  static const List<String> adminEmails = [
    'donshaji2004@gmail.com',
    // 'another_admin@mail.com', // Placeholder 1
    // 'future_admin@mail.com',  // Placeholder 2
  ];

  static bool isAdmin(String? email) {
    if (email == null) return false;
    return adminEmails.contains(email.toLowerCase());
  }
}
