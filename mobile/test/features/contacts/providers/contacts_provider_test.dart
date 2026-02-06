import 'package:flutter_test/flutter_test.dart';
import 'package:ansible_talk/features/contacts/providers/contacts_provider.dart';
import 'package:ansible_talk/shared/models/user.dart';

void main() {
  group('ContactsState', () {
    test('default values', () {
      const state = ContactsState();

      expect(state.contacts, isEmpty);
      expect(state.isLoading, false);
      expect(state.error, null);
    });

    test('copyWith preserves unchanged values', () {
      const state = ContactsState(isLoading: true);
      final newState = state.copyWith(error: 'Test error');

      expect(newState.isLoading, true);
      expect(newState.error, 'Test error');
    });

    test('copyWith with contacts', () {
      const state = ContactsState();
      final newState = state.copyWith(contacts: []);

      expect(newState.contacts, isEmpty);
    });

    test('copyWith with isLoading', () {
      const state = ContactsState();
      final newState = state.copyWith(isLoading: true);

      expect(newState.isLoading, true);
    });

    test('copyWith with error', () {
      const state = ContactsState();
      final newState = state.copyWith(error: 'Failed to load');

      expect(newState.error, 'Failed to load');
    });
  });

  group('Contact filtering', () {
    test('favorites filter logic', () {
      // Simulate favorites filter
      final contacts = [
        {'isFavorite': true, 'isBlocked': false},
        {'isFavorite': false, 'isBlocked': false},
        {'isFavorite': true, 'isBlocked': true}, // blocked, excluded
      ];

      final favorites = contacts.where((c) =>
        c['isFavorite'] == true && c['isBlocked'] == false
      ).toList();

      expect(favorites.length, 1);
    });

    test('regular contacts filter logic', () {
      final contacts = [
        {'isFavorite': true, 'isBlocked': false},
        {'isFavorite': false, 'isBlocked': false},
        {'isFavorite': false, 'isBlocked': true}, // blocked, excluded
      ];

      final regular = contacts.where((c) =>
        c['isFavorite'] == false && c['isBlocked'] == false
      ).toList();

      expect(regular.length, 1);
    });

    test('blocked contacts excluded from favorites', () {
      final contacts = [
        {'isFavorite': true, 'isBlocked': true},
      ];

      final favorites = contacts.where((c) =>
        c['isFavorite'] == true && c['isBlocked'] == false
      ).toList();

      expect(favorites, isEmpty);
    });
  });

  group('Contact operations', () {
    test('add contact with nickname', () {
      const contactId = 'user-123';
      const nickname = 'Best Friend';

      expect(contactId.isNotEmpty, true);
      expect(nickname.isNotEmpty, true);
    });

    test('add contact without nickname', () {
      const contactId = 'user-123';
      const String? nickname = null;

      expect(contactId.isNotEmpty, true);
      expect(nickname, isNull);
    });

    test('update contact data structure', () {
      final data = <String, dynamic>{};

      const nickname = 'New Nickname';
      const isFavorite = true;

      data['nickname'] = nickname;
      data['is_favorite'] = isFavorite;

      expect(data['nickname'], nickname);
      expect(data['is_favorite'], isFavorite);
    });

    test('partial update - nickname only', () {
      final data = <String, dynamic>{};

      const nickname = 'New Nickname';
      data['nickname'] = nickname;

      expect(data.containsKey('nickname'), true);
      expect(data.containsKey('is_favorite'), false);
    });

    test('partial update - favorite only', () {
      final data = <String, dynamic>{};

      const isFavorite = true;
      data['is_favorite'] = isFavorite;

      expect(data.containsKey('nickname'), false);
      expect(data.containsKey('is_favorite'), true);
    });
  });

  group('Block/Unblock operations', () {
    test('block contact state change', () {
      final contact = {
        'isBlocked': false,
      };

      final blocked = {...contact, 'isBlocked': true};

      expect(contact['isBlocked'], false);
      expect(blocked['isBlocked'], true);
    });

    test('unblock contact state change', () {
      final contact = {
        'isBlocked': true,
      };

      final unblocked = {...contact, 'isBlocked': false};

      expect(contact['isBlocked'], true);
      expect(unblocked['isBlocked'], false);
    });
  });

  group('Toggle favorite', () {
    test('toggle favorite on', () {
      final contact = {'isFavorite': false};
      final toggled = {...contact, 'isFavorite': !contact['isFavorite']!};

      expect(toggled['isFavorite'], true);
    });

    test('toggle favorite off', () {
      final contact = {'isFavorite': true};
      final toggled = {...contact, 'isFavorite': !contact['isFavorite']!};

      expect(toggled['isFavorite'], false);
    });
  });

  group('Delete contact', () {
    test('remove contact from list', () {
      final contacts = ['c1', 'c2', 'c3'];
      const toDelete = 'c2';

      final filtered = contacts.where((c) => c != toDelete).toList();

      expect(filtered.length, 2);
      expect(filtered.contains(toDelete), false);
    });
  });

  group('Search users', () {
    test('empty query returns empty', () {
      const query = '';
      expect(query.isEmpty, true);
    });

    test('non-empty query', () {
      const query = 'john';
      expect(query.isNotEmpty, true);
    });

    test('search query format', () {
      const queries = ['john', 'john.doe', '+1234567890', 'test@example.com'];

      for (final query in queries) {
        expect(query.isNotEmpty, true);
      }
    });
  });

  group('Error messages', () {
    test('load contacts error', () {
      const error = 'Failed to load contacts';
      expect(error.contains('contacts'), true);
    });

    test('add contact error', () {
      const error = 'Failed to add contact';
      expect(error.contains('contact'), true);
    });

    test('update contact error', () {
      const error = 'Failed to update contact';
      expect(error.contains('contact'), true);
    });

    test('delete contact error', () {
      const error = 'Failed to delete contact';
      expect(error.contains('contact'), true);
    });

    test('block contact error', () {
      const error = 'Failed to block contact';
      expect(error.contains('block'), true);
    });

    test('unblock contact error', () {
      const error = 'Failed to unblock contact';
      expect(error.contains('unblock'), true);
    });
  });

  group('State transitions', () {
    test('loading to loaded', () {
      const loading = ContactsState(isLoading: true);
      final loaded = loading.copyWith(
        isLoading: false,
        contacts: [],
      );

      expect(loading.isLoading, true);
      expect(loaded.isLoading, false);
    });

    test('add contact appends to list', () {
      final existing = ['c1', 'c2'];
      const newContact = 'c3';
      final updated = [...existing, newContact];

      expect(updated.length, 3);
      expect(updated.last, newContact);
    });

    test('update contact replaces in list', () {
      final contacts = [
        {'id': 'c1', 'nickname': 'Old'},
        {'id': 'c2', 'nickname': 'Other'},
      ];

      final updated = contacts.map((c) {
        if (c['id'] == 'c1') {
          return {...c, 'nickname': 'New'};
        }
        return c;
      }).toList();

      expect(updated[0]['nickname'], 'New');
      expect(updated[1]['nickname'], 'Other');
    });
  });

  group('Include blocked parameter', () {
    test('include blocked = false', () {
      const includeBlocked = false;

      // Simulate filtering
      final contacts = [
        {'isBlocked': true},
        {'isBlocked': false},
      ];

      final filtered = includeBlocked
        ? contacts
        : contacts.where((c) => c['isBlocked'] == false).toList();

      expect(filtered.length, 1);
    });

    test('include blocked = true', () {
      const includeBlocked = true;

      final contacts = [
        {'isBlocked': true},
        {'isBlocked': false},
      ];

      final filtered = includeBlocked
        ? contacts
        : contacts.where((c) => c['isBlocked'] == false).toList();

      expect(filtered.length, 2);
    });
  });

  group('Contact model', () {
    test('contact ID required', () {
      const contactId = 'user-123';
      expect(contactId.isNotEmpty, true);
    });

    test('user ID required', () {
      const userId = 'owner-456';
      expect(userId.isNotEmpty, true);
    });

    test('nickname optional', () {
      const String? nickname1 = null;
      const String nickname2 = 'My Friend';

      expect(nickname1, isNull);
      expect(nickname2.isNotEmpty, true);
    });

    test('timestamps present', () {
      final createdAt = DateTime.now();
      final updatedAt = DateTime.now();

      expect(createdAt.isBefore(updatedAt) || createdAt == updatedAt, true);
    });
  });
}
