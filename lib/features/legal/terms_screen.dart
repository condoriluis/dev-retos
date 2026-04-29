import 'package:flutter/material.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Términos y Condiciones')),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Términos de Servicio',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text(
              'Última actualización: 15 de Abril de 2026',
              style: TextStyle(color: Colors.grey),
            ),
            SizedBox(height: 24),
            Text(
              '1. Aceptación de los Términos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Al utilizar la aplicación Dev Retos, usted acepta cumplir y estar sujeto a estos términos y condiciones de uso. Si no está de acuerdo con alguna parte de estos términos, no podrá utilizar nuestra aplicación.',
            ),
            SizedBox(height: 24),
            Text(
              '2. Uso del Servicio',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Usted se compromete a utilizar la aplicación únicamente para fines legales y de una manera que no infrinja los derechos de terceros ni restrinja o inhiba el uso y disfrute de la aplicación por parte de cualquier tercero.',
            ),
            SizedBox(height: 24),
            Text(
              '3. Propiedad Intelectual',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Todo el contenido incluido en esta aplicación, como retos, textos, gráficos, logotipos e imágenes, es propiedad de Dev Retos o sus proveedores de contenido y está protegido por las leyes de derechos de autor.',
            ),
            SizedBox(height: 24),
            Text(
              '4. Membresía PRO',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'La suscripción PRO otorga acceso a retos exclusivos. Las suscripciones son personales y no transferibles. Los pagos se procesan a través de las tiendas oficiales (Google Play Store).',
            ),
            SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}
