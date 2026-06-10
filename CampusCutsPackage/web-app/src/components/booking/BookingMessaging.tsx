/**
 * Booking Messaging Component
 * 
 * Real-time messaging between barber and customer
 */

import React, { useState, useEffect, useRef } from 'react';
import { Send, MessageSquare } from 'lucide-react';
import Button from '../Button';
import Card from '../Card';
import axios from 'axios';
import toast from 'react-hot-toast';

interface Message {
  messageId: string;
  senderId: string;
  senderType: 'barber' | 'customer';
  senderName: string;
  message: string;
  read: boolean;
  createdAt: string;
}

interface Props {
  bookingId: string;
  userId: string;
  userType: 'barber' | 'customer';
  otherPartyName: string;
}

export default function BookingMessaging({ bookingId, userId, userType, otherPartyName }: Props) {
  const [messages, setMessages] = useState<Message[]>([]);
  const [newMessage, setNewMessage] = useState('');
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    fetchMessages();
    const interval = setInterval(fetchMessages, 5000); // Poll every 5 seconds
    return () => clearInterval(interval);
  }, [bookingId]);

  useEffect(() => {
    scrollToBottom();
  }, [messages]);

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  };

  const fetchMessages = async () => {
    try {
      const response = await axios.get(
        `http://localhost:3001/api/booking-requests/${bookingId}/messages?userId=${userId}`
      );
      setMessages(response.data.messages || []);
      setLoading(false);
    } catch (error) {
      console.error('Failed to fetch messages:', error);
      setLoading(false);
    }
  };

  const handleSend = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!newMessage.trim()) return;

    setSending(true);
    try {
      await axios.post(
        `http://localhost:3001/api/booking-requests/${bookingId}/messages`,
        {
          senderId: userId,
          senderType: userType,
          message: newMessage.trim(),
        }
      );

      setNewMessage('');
      fetchMessages();
    } catch (error) {
      console.error('Failed to send message:', error);
      toast.error('Failed to send message');
    } finally {
      setSending(false);
    }
  };

  if (loading) {
    return (
      <Card>
        <div className="text-center py-8">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary-400 mx-auto"></div>
          <p className="mt-2 text-gray-600">Loading messages...</p>
        </div>
      </Card>
    );
  }

  return (
    <Card>
      <div className="flex items-center gap-2 mb-4 pb-4 border-b">
        <MessageSquare className="w-5 h-5 text-primary-400" />
        <h3 className="font-semibold text-gray-900">Messages with {otherPartyName}</h3>
      </div>

      {/* Messages List */}
      <div className="space-y-3 mb-4 max-h-96 overflow-y-auto">
        {messages.length === 0 ? (
          <div className="text-center py-8 text-gray-500">
            <MessageSquare className="w-12 h-12 text-gray-300 mx-auto mb-2" />
            <p>No messages yet</p>
            <p className="text-sm mt-1">Start the conversation!</p>
          </div>
        ) : (
          messages.map((msg) => {
            const isOwn = msg.senderType === userType;
            return (
              <div
                key={msg.messageId}
                className={`flex ${isOwn ? 'justify-end' : 'justify-start'}`}
              >
                <div
                  className={`max-w-[70%] rounded-lg px-4 py-2 ${
                    isOwn
                      ? 'bg-primary-400 text-white'
                      : 'bg-gray-100 text-gray-900'
                  }`}
                >
                  {!isOwn && (
                    <p className="text-xs font-medium mb-1 opacity-75">
                      {msg.senderName}
                    </p>
                  )}
                  <p className="text-sm">{msg.message}</p>
                  <p
                    className={`text-xs mt-1 ${
                      isOwn ? 'text-primary-200' : 'text-gray-500'
                    }`}
                  >
                    {new Date(msg.createdAt).toLocaleTimeString([], {
                      hour: '2-digit',
                      minute: '2-digit',
                    })}
                  </p>
                </div>
              </div>
            );
          })
        )}
        <div ref={messagesEndRef} />
      </div>

      {/* Message Input */}
      <form onSubmit={handleSend} className="flex gap-2">
        <input
          type="text"
          value={newMessage}
          onChange={(e) => setNewMessage(e.target.value)}
          placeholder="Type your message..."
          className="flex-1 px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-transparent"
          disabled={sending}
        />
        <Button
          type="submit"
          disabled={sending || !newMessage.trim()}
          size="sm"
          className="flex items-center gap-2"
        >
          <Send className="w-4 h-4" />
          Send
        </Button>
      </form>
    </Card>
  );
}

