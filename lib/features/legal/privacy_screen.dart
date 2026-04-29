import 'package:flutter/material.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Políticas de Privacidad')),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Aviso de Privacidad',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text(
              'Última actualización: 15 de Abril de 2026',
              style: TextStyle(color: Colors.grey),
            ),
            SizedBox(height: 24),
            Text(
              '1. Información que Recopilamos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Recopilamos información básica de su cuenta de Google (nombre, email y foto de perfil) cuando inicia sesión a través de Firebase Auth. También registramos su progreso en los retos para generar las estadísticas de su perfil.',
            ),
            SizedBox(height: 24),
            Text(
              '2. Uso de los Datos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Sus datos se utilizan para personalizar su experiencia, mostrar su posición en el ranking global y gestionar su suscripción PRO de manera segura.',
            ),
            SizedBox(height: 24),
            Text(
              '3. Seguridad',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Implementamos medidas de seguridad para proteger su información. Al utilizar Firebase y Turso, sus datos están cifrados y protegidos por estándares de la industria.',
            ),
            SizedBox(height: 24),
            Text(
              '4. Eliminación de Datos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Usted tiene derecho a eliminar su cuenta en cualquier momento desde la configuración del perfil. Este proceso borrará sus credenciales de autenticación.',
            ),
            SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}
