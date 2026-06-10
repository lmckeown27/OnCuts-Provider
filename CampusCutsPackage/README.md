# CampusCuts

**A campus marketplace connecting students with barbers.**

---

## 📖 Overview

CampusCuts is a mobile-first web platform that connects college students with on-campus barbers. The platform streamlines the entire haircut booking experience—from discovering barbers at your university to scheduling appointments, messaging, and secure payment processing.

### What is CampusCuts?

CampusCuts solves a common problem on college campuses: finding reliable, affordable haircuts nearby. Instead of searching for off-campus barbershops or relying on word-of-mouth, students can browse verified barbers right at their university, view portfolios, check availability, and book appointments in minutes.

### How It Works

**For Students (Consumers):**
1. **Select your university** from 100+ supported campuses
2. **Browse barbers** - view profiles, portfolios, ratings, and pricing
3. **Book an appointment** - choose a service, date, time, and location
4. **Message your barber** - coordinate details or ask questions
5. **Get your haircut** - meet at the scheduled time and location
6. **Pay after service** - pay with card or cash, add an optional tip
7. **Leave a review** - help other students find great barbers

**For Barbers:**
1. **Apply to join** - submit an application with experience and portfolio
2. **Set your schedule** - define weekly availability with flexible time slots
3. **List your services** - set custom pricing for different haircut types
4. **Receive bookings** - get notified when students request appointments
5. **Accept or negotiate** - message students to confirm details
6. **Complete the service** - mark as done when finished
7. **Get paid** - receive payment minus a small platform fee

### Key Benefits

| For Students | For Barbers |
|--------------|-------------|
| Find barbers at your campus | Reach students at your school |
| View portfolios before booking | Flexible scheduling |
| Real-time availability | Build your client base |
| Secure post-service payments | Track earnings and reviews |
| No upfront payment required | Professional portfolio hosting |
| Rate and review barbers | Instagram integration |

### Platform Highlights

- **100+ Universities** - Campuses across the United States
- **Real-Time Messaging** - Chat directly with barbers before and after booking
- **Smart Scheduling** - 1-hour appointment blocks prevent double-bookings
- **Flexible Payments** - Pay with card (Stripe) or cash after service
- **Mobile-First Design** - Optimized for phones, works on all devices
- **Campus Manager Tools** - University staff can oversee local barbers

---

## 🚀 Quick Start

```bash
# Clone repository
git clone https://github.com/lmckeown27/CampusCuts.git
cd CampusCuts

# Backend setup
cd backend
npm install --legacy-peer-deps
npm run build

# Frontend setup
cd ../web-app
npm install
npm run build

# Start services
pm2 start backend/dist/index.js --name campuscuts-backend
```

---

## 📋 Tech Stack

### **Backend**
- Node.js + TypeScript + Express
- PostgreSQL (database with raw queries)
- Stripe (payments)
- Socket.IO (real-time messaging & updates)
- JWT authentication
- Nodemailer (SMTP email)
- AWS S3 (image storage)
- Luxon (timezone handling)

### **Frontend**
- React 18 + TypeScript + Vite
- TailwindCSS
- Zustand (state management)
- React Router v6
- Lucide React (icons)
- React Hot Toast (notifications)
- **Typography:** Source Serif 4 (Medium weight, 500) - Google Fonts

---

## 🗄️ Database Setup

### **1. Create Database**

```bash
# Create PostgreSQL database
sudo -u postgres psql
CREATE DATABASE campuscuts;
CREATE USER campuscuts_user WITH PASSWORD 'your_secure_password';
GRANT ALL PRIVILEGES ON DATABASE campuscuts TO campuscuts_user;
\c campuscuts
GRANT ALL ON SCHEMA public TO campuscuts_user;
```

### **2. Run Migrations**

```bash
cd backend
# Run all migrations in order
for f in src/database/migrations/*.sql; do
  sudo -u postgres psql -d campuscuts -f "$f"
done

# Seed campus data
sudo -u postgres psql -d campuscuts -f src/database/seed_campuses.sql
```

---

## ⚙️ Environment Variables

### **Backend `.env`**

```bash
# Server
NODE_ENV=production
PORT=3001

# Database
DATABASE_URL="postgresql://campuscuts_user:password@localhost:5432/campuscuts?schema=public"

# JWT Authentication
JWT_SECRET=your_64_character_secret_here
JWT_REFRESH_SECRET=your_64_character_refresh_secret_here
JWT_EXPIRES_IN=7d
JWT_REFRESH_EXPIRES_IN=30d

# Payment System
STRIPE_SECRET_KEY=sk_live_your_stripe_key
STRIPE_WEBHOOK_SECRET=whsec_your_webhook_secret

# Email (SMTP)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your_email@gmail.com
SMTP_PASS=your_16_char_app_password
EMAIL_FROM="CampusCuts <noreply@campuscuts.com>"
FRONTEND_URL=https://campuscut.com
AUTO_VERIFY_EMAILS=false

# AWS S3 (Image Storage)
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
AWS_REGION=us-west-1
S3_BUCKET_NAME=campuscut-images
```

### **Frontend `.env`**

```bash
VITE_API_URL=https://campuscut.com/api/v1
```

---

## 💳 Payment System

### **Stripe Integration**

Secure payment flow with post-service payments:

```
Barber marks complete → Consumer receives email → Consumer pays → Funds to barber
```

**Payment Options:**
- **Pay with Card** - Stripe payment processing with optional tips
- **Pay with Cash** - Mark as paid for in-person cash transactions

**Features:**
- Post-service payment collection
- Optional tip selection (15%, 20%, 25%, or custom)
- Real-time payment status updates via WebSocket
- Email notification with payment link when service completes
- Platform fee: 15% (configurable)

---

## 🔐 Authentication

### **JWT-Based Authentication**

- Access tokens (7 days default)
- Refresh tokens (30 days default)
- Role-based access control
- Email verification required

### **User Roles**

| Role | Description |
|------|-------------|
| `student` | Consumer - can book appointments |
| `barber` | Service provider - manages bookings |
| `campus_manager` | Oversees campus barbers and applications |
| `ADMIN` | Full platform access |

### **Generate Secrets**

```bash
# Generate JWT_SECRET (64 characters)
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"

# Generate JWT_REFRESH_SECRET (64 characters)
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

---

## 📧 Email Notifications

Automated email notifications for:

- **Registration** - 6-digit verification code
- **Booking Confirmation** - When barber accepts booking
- **Service Complete** - Payment link sent to consumer
- **Payment Received** - Confirmation to both parties

**Configure SMTP:**
- Gmail: Use app-specific password (16 characters)
- Set `AUTO_VERIFY_EMAILS=false` for production

---

## 🔗 API Keys Required

### **Essential (Required)**

| Service | Key | Where to Get |
|---------|-----|--------------|
| **Stripe** | `STRIPE_SECRET_KEY` | https://dashboard.stripe.com/apikeys |
| **Stripe Webhooks** | `STRIPE_WEBHOOK_SECRET` | https://dashboard.stripe.com/webhooks |
| **Gmail SMTP** | `SMTP_PASS` | Gmail → Security → App Passwords |
| **AWS S3** | `AWS_ACCESS_KEY_ID` | AWS IAM Console |

---

## 🚢 Deployment

### **Production Deployment**

```bash
# 1. Clone on server
git clone https://github.com/lmckeown27/CampusCuts.git
cd CampusCuts

# 2. Setup database
sudo -u postgres createdb campuscuts
for f in backend/src/database/migrations/*.sql; do
  sudo -u postgres psql -d campuscuts -f "$f"
done

# 3. Configure environment
cp backend/.env.example backend/.env
nano backend/.env  # Add your keys

# 4. Install dependencies
cd backend && npm install --legacy-peer-deps
cd ../web-app && npm install

# 5. Build
cd ../backend && npm run build
cd ../web-app && npm run build

# 6. Start with PM2
pm2 start backend/dist/index.js --name campuscuts-backend
pm2 startup
pm2 save

# 7. Setup nginx reverse proxy
sudo nano /etc/nginx/sites-available/campuscuts
sudo nginx -t && sudo systemctl reload nginx
```

---

## 📱 Key Features

### **For Consumers (Students)**
- ✅ Browse barbers by university campus
- ✅ Dynamic university selection (100+ campuses)
- ✅ Real-time availability with time slot blocking
- ✅ Book appointments with date/time picker
- ✅ Real-time messaging with barbers
- ✅ Pay with card or cash after service
- ✅ Optional tips for barbers
- ✅ Rate and review barbers
- ✅ View booking status in real-time

### **For Barbers**
- ✅ Manage weekly availability schedule
- ✅ Multiple time intervals per day
- ✅ Accept/reject booking requests
- ✅ Real-time messaging with consumers
- ✅ Mark services as complete
- ✅ Portfolio/gallery management (S3)
- ✅ Instagram integration
- ✅ Custom service pricing
- ✅ Visibility toggle (hide/show profile)

### **For Campus Managers**
- ✅ View all campus barbers (including hidden)
- ✅ Review barber applications
- ✅ Schedule interviews via email
- ✅ View campus booking statistics
- ✅ Filter bookings by barber and date

### **Platform Features**
- ✅ Email verification
- ✅ JWT authentication with refresh tokens
- ✅ Role-based access control
- ✅ Real-time WebSocket updates
- ✅ 1-hour appointment time blocking
- ✅ Time conflict prevention
- ✅ Responsive mobile-first design
- ✅ Unread message notifications

---

## 🏗️ Architecture

### **System Architecture**

```
┌─────────────────────────────────────────┐
│           Frontend (React)              │
│  Booking UI, Messages, User Dashboard   │
└──────────────┬──────────────────────────┘
               │ REST API + WebSocket
┌──────────────▼──────────────────────────┐
│       Backend (Node.js/Express)         │
│   Routes, Controllers, Services         │
└──────┬─────────────┬───────────┬────────┘
       │             │           │
┌──────▼─────┐ ┌─────▼─────┐ ┌───▼────┐
│ PostgreSQL │ │   Stripe  │ │  AWS   │
│  Database  │ │ Payments  │ │   S3   │
└────────────┘ └───────────┘ └────────┘
```

### **Real-Time Communication**

```
Socket.IO Events:
├── booking-update     → Booking status changes
├── payment-received   → Payment confirmations
├── new-message        → Chat messages
└── notification       → System notifications
```

### **Booking Flow**

```
1. Consumer selects barber & time
2. Consumer submits booking request
3. Barber receives notification
4. Barber accepts/rejects
5. Service is performed
6. Barber marks complete
7. Consumer receives payment email
8. Consumer pays (card or cash)
9. Booking marked as PAID
```

---

## 🛠️ Development

### **Backend Development**

```bash
cd backend
npm run dev  # Start with nodemon (auto-reload)
```

### **Frontend Development**

```bash
cd web-app
npm run dev  # Start Vite dev server (port 5173)
```

### **Database Management**

```bash
# Connect to database
sudo -u postgres psql -d campuscuts

# Check tables
\dt

# View barbers
SELECT u.first_name, u.last_name, u.email, b."isActive" 
FROM barbers b 
JOIN users u ON b."userId" = u.id;

# View bookings
SELECT * FROM bookings ORDER BY "createdAt" DESC LIMIT 10;
```

See `POSTGRES_COMMANDS.md` for comprehensive database queries.

---

## 🧪 Testing

### **Test Payment System**

```bash
# Stripe test cards
4242 4242 4242 4242  # Success
4000 0000 0000 0002  # Decline
4000 0000 0000 9995  # Insufficient funds
```

### **Test Endpoints**

```bash
# Health check
curl http://localhost:3001/health

# Get campuses
curl http://localhost:3001/api/v1/campus

# Get barbers by campus
curl http://localhost:3001/api/v1/barbers?campusId=<campus-id>
```

---

## 📊 Database Schema

### **Key Tables**

| Table | Description |
|-------|-------------|
| `users` | All users (students, barbers, managers, admins) |
| `barbers` | Barber profiles, availability, pricing |
| `bookings` | Appointment records with status tracking |
| `reviews` | Consumer reviews and ratings |
| `campuses` | University/college data |
| `conversations` | Messaging threads |
| `messages` | Individual chat messages |
| `barber_applications` | Registered user applications |
| `guest_barber_applications` | Non-registered applications |
| `notifications` | In-app notifications |

### **Booking Statuses**

| Status | Description |
|--------|-------------|
| `PENDING` | Awaiting barber response |
| `ACCEPTED` | Barber accepted, service upcoming |
| `COMPLETED` | Service finished, awaiting payment |
| `PAID` | Payment received |
| `CANCELLED` | Cancelled by consumer |
| `REJECTED` | Rejected by barber |

---

## 🔧 Troubleshooting

### **Backend won't start**

```bash
# Check logs
pm2 logs campuscuts-backend --lines 50

# Rebuild
cd backend
rm -rf dist
npm run build
pm2 restart campuscuts-backend
```

### **Database connection failed**

```bash
# Test connection
sudo -u postgres psql -d campuscuts -c "SELECT 1;"

# Check .env
grep DATABASE_URL backend/.env

# Verify user exists
sudo -u postgres psql -c "\du"
```

### **Email not sending**

```bash
# Check SMTP config
grep SMTP backend/.env

# Verify app password is correct (16 chars, no spaces)
# Check spam folder
# Verify EMAIL_FROM format
```

### **Images not uploading**

```bash
# Check S3 config
grep AWS backend/.env
grep S3 backend/.env

# Verify bucket permissions and CORS
```

### **Build errors**

```bash
# Clean install
cd backend
rm -rf node_modules package-lock.json
npm cache clean --force
npm install --legacy-peer-deps
npm run build
```

---

## 📈 Performance

### **Current Metrics**

- **Payment processing:** ~2-3 seconds (Stripe)
- **Database queries:** <50ms average
- **API response time:** <200ms average
- **WebSocket latency:** <100ms
- **Concurrent users:** 100+ supported

### **Optimization**

- PostgreSQL connection pooling (configured)
- PM2 cluster mode for multiple processes
- Nginx reverse proxy with caching
- S3 for static asset storage
- Cache-Control headers for availability data

---

## 🔒 Security

### **Implemented**

- ✅ JWT authentication with refresh tokens
- ✅ Password hashing (bcrypt)
- ✅ Email verification required
- ✅ Role-based access control
- ✅ SQL injection prevention (parameterized queries)
- ✅ CORS configuration
- ✅ HTTPS in production
- ✅ Rate limiting on auth endpoints
- ✅ Input validation and sanitization

### **Recommendations**

- Rotate JWT secrets every 90 days
- Enable 2FA for admin accounts
- Regular security audits
- Keep dependencies updated
- Monitor for unusual activity

---

## 🚀 Roadmap

### **Phase 1: MVP ✅ Complete**
- ✅ Stripe payments (post-service)
- ✅ Email verification
- ✅ Booking system with availability
- ✅ Real-time messaging
- ✅ Review system
- ✅ Campus manager dashboard
- ✅ Pay with cash option

### **Phase 2: Enhancement (In Progress)**
- ⏳ Push notifications
- ⏳ Advanced analytics dashboard
- ⏳ Recurring appointments
- ⏳ Waitlist feature

### **Phase 3: Scale**
- ⏳ Multi-campus expansion tools
- ⏳ Mobile apps (React Native)
- ⏳ Loyalty/rewards program
- ⏳ Barber scheduling assistant

---

## 📂 Project Structure

```
CampusCuts/
├── backend/
│   ├── src/
│   │   ├── controllers/     # Route handlers
│   │   ├── routes/          # API endpoints
│   │   ├── services/        # Business logic
│   │   ├── middleware/      # Auth, validation
│   │   ├── database/        # Migrations, seeds
│   │   └── index.ts         # Entry point
│   └── dist/                # Compiled output
├── web-app/
│   ├── src/
│   │   ├── components/      # Reusable UI
│   │   ├── pages/           # Route pages
│   │   ├── services/        # API clients
│   │   ├── stores/          # Zustand state
│   │   ├── hooks/           # Custom hooks
│   │   └── types/           # TypeScript types
│   └── dist/                # Built assets
├── POSTGRES_COMMANDS.md     # Database queries
└── README.md                # This file
```

---

## 📞 Support

- **Issues:** Open a GitHub issue
- **Email:** support@campuscut.com
- **Production URL:** https://campuscut.com

---

## 📄 License

MIT License - See LICENSE file for details

---

**Built with ❤️ for campus communities**

Platform Version: 2.0.0  
Last Updated: February 2026
