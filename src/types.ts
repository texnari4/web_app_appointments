// Lightweight types for Services feature
export interface ServiceGroup {
  id: string;
  name: string;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface ServiceItem {
  id: string;
  groupId: string; // FK to ServiceGroup.id
  name: string;
  description?: string;
  price: number; // in major currency units
  durationMinutes: number;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface ServicesDbShape {
  groups: ServiceGroup[];
  items: ServiceItem[];
}
