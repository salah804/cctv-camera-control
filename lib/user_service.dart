import 'package:shared_preferences/shared_preferences.dart';

class UserService {
  // Save username and id during login
  static Future<void> saveUserData(String username, String id) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', username);
    await prefs.setString('id', id);
  }

  // Retrieve username from SharedPreferences
  static Future<String> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('username') ?? '';
  }

  // Retrieve user ID from SharedPreferences
  static Future<String> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('id') ?? '';
  }
}
