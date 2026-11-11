
import 'package:flutter/material.dart';
import 'package:google_sign_in_web/web_only.dart' as google_web;

Widget buildGoogleWebButton() {
  return google_web.renderButton(
    configuration: google_web.GSIButtonConfiguration(
      locale: 'en',
    ),
  );
}
