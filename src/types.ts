
export interface Master {
  id: string;
  name: string;
  phone: string;
  avatarUrl?: string;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
}

export type AppointmentStatus = "scheduled" | "canceled" | "completed";

export interface Appointment {
  id: string;
  masterId: string;
  customerName: string;
  customerPhone: string;
  service?: string;
  notes?: string;
  start: string; // ISO
  end: string;   // ISO
  status: AppointmentStatus;
  createdAt: string;
  updatedAt: string;
}

export interface DbShape {
  masters: Master[];
  appointments: Appointment[];
}
