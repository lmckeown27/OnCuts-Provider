import express from 'express';
import { authenticate } from '../middleware/auth';
import * as zkloginController from '../controllers/zklogin.controller';

const router = express.Router();

router.post('/salt', zkloginController.postZkLoginSalt);
router.post('/google-complete', authenticate, zkloginController.postZkLoginGoogleComplete);
router.put('/address', authenticate, zkloginController.putZkLoginAddress);

export default router;
