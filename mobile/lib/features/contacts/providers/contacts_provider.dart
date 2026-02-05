import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/models/user.dart';

class ContactsState {
  final List<Contact> contacts;
  final bool isLoading;
  final String? error;

  const ContactsState({
    this.contacts = const [],
    this.isLoading = false,
    this.error,
  });

  ContactsState copyWith({
    List<Contact>? contacts,
    bool? isLoading,
    String? error,
  }) {
    return ContactsState(
      contacts: contacts ?? this.contacts,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  List<Contact> get favorites =>
      contacts.where((c) => c.isFavorite && !c.isBlocked).toList();

  List<Contact> get regular =>
      contacts.where((c) => !c.isFavorite && !c.isBlocked).toList();
}

class ContactsNotifier extends StateNotifier<ContactsState> {
  final ApiClient _apiClient;

  ContactsNotifier(this._apiClient) : super(const ContactsState()) {
    loadContacts();
  }

  Future<void> loadContacts({bool includeBlocked = false}) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _apiClient.getContacts(includeBlocked: includeBlocked);
      final contacts = (response.data as List)
          .map((json) => Contact.fromJson(json))
          .toList();

      state = state.copyWith(contacts: contacts, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load contacts',
      );
    }
  }

  Future<Contact?> addContact(String contactId, {String? nickname}) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _apiClient.addContact(contactId, nickname: nickname);
      final contact = Contact.fromJson(response.data);

      state = state.copyWith(
        contacts: [...state.contacts, contact],
        isLoading: false,
      );

      return contact;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to add contact',
      );
      return null;
    }
  }

  Future<void> updateContact(
    String contactId, {
    String? nickname,
    bool? isFavorite,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (nickname != null) data['nickname'] = nickname;
      if (isFavorite != null) data['is_favorite'] = isFavorite;

      final response = await _apiClient.updateContact(contactId, data);
      final updatedContact = Contact.fromJson(response.data);

      state = state.copyWith(
        contacts: state.contacts.map((c) {
          return c.contactId == contactId ? updatedContact : c;
        }).toList(),
      );
    } catch (e) {
      state = state.copyWith(error: 'Failed to update contact');
    }
  }

  Future<void> deleteContact(String contactId) async {
    try {
      await _apiClient.deleteContact(contactId);

      state = state.copyWith(
        contacts: state.contacts.where((c) => c.contactId != contactId).toList(),
      );
    } catch (e) {
      state = state.copyWith(error: 'Failed to delete contact');
    }
  }

  Future<void> blockContact(String contactId) async {
    try {
      await _apiClient.blockContact(contactId);

      state = state.copyWith(
        contacts: state.contacts.map((c) {
          return c.contactId == contactId
              ? Contact(
                  id: c.id,
                  userId: c.userId,
                  contactId: c.contactId,
                  nickname: c.nickname,
                  isBlocked: true,
                  isFavorite: c.isFavorite,
                  createdAt: c.createdAt,
                  updatedAt: DateTime.now(),
                  contact: c.contact,
                )
              : c;
        }).toList(),
      );
    } catch (e) {
      state = state.copyWith(error: 'Failed to block contact');
    }
  }

  Future<void> unblockContact(String contactId) async {
    try {
      await _apiClient.unblockContact(contactId);

      state = state.copyWith(
        contacts: state.contacts.map((c) {
          return c.contactId == contactId
              ? Contact(
                  id: c.id,
                  userId: c.userId,
                  contactId: c.contactId,
                  nickname: c.nickname,
                  isBlocked: false,
                  isFavorite: c.isFavorite,
                  createdAt: c.createdAt,
                  updatedAt: DateTime.now(),
                  contact: c.contact,
                )
              : c;
        }).toList(),
      );
    } catch (e) {
      state = state.copyWith(error: 'Failed to unblock contact');
    }
  }

  Future<void> toggleFavorite(String contactId) async {
    final contact = state.contacts.firstWhere((c) => c.contactId == contactId);
    await updateContact(contactId, isFavorite: !contact.isFavorite);
  }
}

// Providers
final contactsProvider = StateNotifierProvider<ContactsNotifier, ContactsState>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return ContactsNotifier(apiClient);
});

// Search users provider
final searchUsersProvider = FutureProvider.family<List<User>, String>((ref, query) async {
  if (query.isEmpty) return [];

  final apiClient = ref.watch(apiClientProvider);
  final response = await apiClient.searchUsers(query);
  return (response.data as List).map((json) => User.fromJson(json)).toList();
});
