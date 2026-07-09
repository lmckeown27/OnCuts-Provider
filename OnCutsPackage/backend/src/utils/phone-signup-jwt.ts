import jwt from 'jsonwebtoken';

export type PhoneSignupTicketPayload = {
  typ: 'phone_signup_ticket';
  phoneE164: string;
  syntheticEmail: string;
  firstName: string;
  lastName: string;
  role: string;
  campusId: string | null;
};

export const generatePhoneSignupTicket = (
  payload: Omit<PhoneSignupTicketPayload, 'typ'>
): string => {
  const secret = process.env.JWT_SECRET;
  if (!secret) {
    throw new Error('JWT_SECRET not configured');
  }
  const body: PhoneSignupTicketPayload = {
    typ: 'phone_signup_ticket',
    ...payload,
  };
  return jwt.sign(body, secret, {
    expiresIn: '30m',
    issuer: 'campuscuts-api',
    audience: 'phone-signup-complete',
  } as jwt.SignOptions);
};

export const verifyPhoneSignupTicket = (token: string): PhoneSignupTicketPayload => {
  const secret = process.env.JWT_SECRET;
  if (!secret) {
    throw new Error('JWT_SECRET not configured');
  }
  const decoded = jwt.verify(token, secret, {
    issuer: 'campuscuts-api',
    audience: 'phone-signup-complete',
  }) as PhoneSignupTicketPayload;
  if (decoded.typ !== 'phone_signup_ticket') {
    throw new Error('Invalid phone signup token');
  }
  return decoded;
};
