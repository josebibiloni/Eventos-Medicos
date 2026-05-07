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

    // Supabase client
    const SUPABASE_URL = 'https://fycclwcxutzxraheggsj.supabase.co';
    const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ5Y2Nsd2N4dXR6eHJhaGVnZ3NqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc1NzE1MjMsImV4cCI6MjA5MzE0NzUyM30.5wj_Z62ENoe26mx0o-FsvH5zPls2nNxTxiPxTTB_J-8';

    // Obtener configuración de email
    const emailConfigResponse = await fetch(
      `${SUPABASE_URL}/rest/v1/email_configs?company_id=eq.${record.company_id}&active=eq.true&select=*`,
      {
        headers: {
          'apikey': SUPABASE_ANON_KEY,
          'Authorization': `Bearer ${SUPABASE_ANON_KEY}`
        }
      }
    );

    const emailConfigs = await emailConfigResponse.json();
    
    if (!emailConfigs || emailConfigs.length === 0) {
      console.log('No email config found for company:', record.company_id);
      return res.status(200).json({ message: 'No email config' });
    }

    const emailConfig = emailConfigs[0];

    // Obtener nombre de la empresa
    const companyResponse = await fetch(
      `${SUPABASE_URL}/rest/v1/companies?id=eq.${record.company_id}&select=name`,
      {
        headers: {
          'apikey': SUPABASE_ANON_KEY,
          'Authorization': `Bearer ${SUPABASE_ANON_KEY}`
        }
      }
    );

    const companies = await companyResponse.json();
    const companyName = companies[0]?.name || 'Nuestro equipo';

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

              <!-- CTA Button (ejemplo para futuros PDFs) -->
              <!-- 
              <div style="text-align: center; margin: 30px 0;">
                <a href="LINK_AL_PDF" style="display: inline-block; background-color: #0ea5e9; color: white; padding: 14px 28px; text-decoration: none; border-radius: 6px; font-weight: 600; font-size: 16px;">
                  📄 Descargar Catálogo
                </a>
              </div>
              -->
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
