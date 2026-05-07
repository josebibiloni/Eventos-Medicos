// ============================================
// API ENDPOINT - /api/send-email.js
// ============================================
// Este endpoint se ejecuta cuando Supabase llama al webhook
// Ubicación en el repo: /api/send-email.js

export default async function handler(req, res) {
  // Solo aceptar POST
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const { type, table, record, old_record } = req.body;

    // Verificar que es un INSERT en la tabla leads
    if (type !== 'INSERT' || table !== 'leads') {
      return res.status(200).json({ message: 'Ignoring event' });
    }

    console.log('New lead captured:', record);

    // CONFIGURACIÓN HARDCODEADA PARA TESTING
    const emailConfig = {
      resend_api_key: 're_2cAjMZ9V_HnQ7R61eYzWtvXnbfF2jHrqF',
      from_email: 'onboarding@resend.dev',
      from_name: 'Sirex Médica'
    };

    const companyName = 'Sirex Médica';

    // Buscar PDF del catálogo (si existe product_id en el lead)
    // Por ahora usamos un PDF hardcodeado para testing
    const pdfUrl = 'https://fycclwcxutzxraheggsj.supabase.co/storage/v1/object/public/pdfs-catalogo/sirex/catalogo-holter-ecg.pdf';
    const productName = 'Holter ECG - Familia Completa';

    // Preparar el email
    const emailData = {
      from: `${emailConfig.from_name} <${emailConfig.from_email}>`,
      to: 'jose.bibiloni@gmail.com', // HARDCODED para testing
      subject: `Gracias por visitar nuestro stand - ${companyName}`,
      html: `
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
        </head>
        <body style="margin: 0; padding: 20px; font-family: Arial, sans-serif; background-color: #f3f4f6;">
          <div style="max-width: 600px; margin: 0 auto; background-color: white; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">
            
            <!-- Header -->
            <div style="background: linear-gradient(135deg, #0ea5e9 0%, #0284c7 100%); padding: 40px 30px; text-align: center;">
              <h1 style="margin: 0; color: white; font-size: 28px; font-weight: 700;">
                ¡Gracias por visitarnos!
              </h1>
            </div>

            <!-- Body -->
            <div style="padding: 40px 30px;">
              <p style="margin: 0 0 20px; font-size: 16px; line-height: 1.6; color: #374151;">
                Hola <strong>${record.nombre || 'visitante'}</strong>,
              </p>
              
              <p style="margin: 0 0 20px; font-size: 16px; line-height: 1.6; color: #374151;">
                Gracias por visitarnos en el evento. Fue un placer conocerte y compartir información sobre nuestros productos.
              </p>

              <p style="margin: 0 0 20px; font-size: 16px; line-height: 1.6; color: #374151;">
                Estamos a tu disposición para cualquier consulta que tengas sobre nuestros equipos médicos.
              </p>

              <!-- CTA Button para descargar PDF -->
              <div style="text-align: center; margin: 30px 0;">
                <a href="${pdfUrl}" style="display: inline-block; background-color: #0ea5e9; color: white; padding: 14px 28px; text-decoration: none; border-radius: 6px; font-weight: 600; font-size: 16px;">
                  📄 Descargar ${productName}
                </a>
              </div>

              <p style="margin: 20px 0 0; font-size: 14px; line-height: 1.6; color: #6b7280; text-align: center;">
                También podés acceder al catálogo desde este enlace:<br>
                <a href="${pdfUrl}" style="color: #0ea5e9; text-decoration: none;">${pdfUrl}</a>
              </p>
            </div>

            <!-- Footer -->
            <div style="background-color: #f9fafb; padding: 30px; border-top: 1px solid #e5e7eb;">
              <p style="margin: 0 0 10px; color: #6b7280; font-size: 14px; line-height: 1.5;">
                Saludos cordiales,
              </p>
              <p style="margin: 0; color: #111827; font-size: 16px; font-weight: 600;">
                ${companyName}
              </p>
            </div>

          </div>
        </body>
        </html>
      `
    };

    // Enviar vía Resend
    const resendResponse = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${emailConfig.resend_api_key}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(emailData)
    });

    const resendData = await resendResponse.json();

    if (!resendResponse.ok) {
      console.error('Resend error:', resendData);
      return res.status(500).json({ error: 'Failed to send email', details: resendData });
    }

    console.log('✓ Email sent successfully:', resendData);

    return res.status(200).json({ 
      success: true, 
      email_id: resendData.id,
      sent_to: 'jose.bibiloni@gmail.com'
    });

  } catch (error) {
    console.error('Error in send-email endpoint:', error);
    return res.status(500).json({ error: error.message });
  }
}
